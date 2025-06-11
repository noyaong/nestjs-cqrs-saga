import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';

export interface LockOptions {
  ttl?: number; // milliseconds
  retryCount?: number;
  retryDelay?: number; // milliseconds
}

export interface AcquiredLock {
  key: string;
  token: string;
  ttl: number;
  acquiredAt: Date;
}

@Injectable()
export class RedisLockService {
  private readonly logger = new Logger(RedisLockService.name);
  private readonly redis: Redis;
  
  // Lua 스크립트: 안전한 락 해제 (토큰 검증 후 삭제)
  private readonly unlockScript = `
    if redis.call("GET", KEYS[1]) == ARGV[1] then
      return redis.call("DEL", KEYS[1])
    else
      return 0
    end
  `;
  
  // Lua 스크립트: 락 갱신 (토큰 검증 후 TTL 연장)
  private readonly renewScript = `
    if redis.call("GET", KEYS[1]) == ARGV[1] then
      return redis.call("PEXPIRE", KEYS[1], ARGV[2])
    else
      return 0
    end
  `;

  constructor(private readonly configService: ConfigService) {
    this.redis = new Redis({
      host: this.configService.get<string>('REDIS_HOST', 'localhost'),
      port: this.configService.get<number>('REDIS_PORT', 6379),
      password: this.configService.get<string>('REDIS_PASSWORD'),
      db: this.configService.get<number>('REDIS_DB', 0),
      maxRetriesPerRequest: 3,
      lazyConnect: true,
    });

    this.redis.on('connect', () => {
      this.logger.log('Redis connected for distributed locking');
    });

    this.redis.on('error', (error) => {
      this.logger.error('Redis connection error:', error);
    });
  }

  /**
   * 분산락 획득
   * @param key 락 키
   * @param options 락 옵션
   * @returns 성공시 AcquiredLock, 실패시 null
   */
  async acquireLock(
    key: string, 
    options: LockOptions = {}
  ): Promise<AcquiredLock | null> {
    const {
      ttl = 30000, // 기본 30초
      retryCount = 3,
      retryDelay = 100
    } = options;

    const token = this.generateToken();
    const lockKey = `lock:${key}`;

    for (let attempt = 0; attempt <= retryCount; attempt++) {
      try {
        // SET key value NX PX milliseconds
        const result = await this.redis.set(
          lockKey, 
          token, 
          'PX', ttl, // PX: milliseconds
          'NX'       // NX: Not eXists
        );

        if (result === 'OK') {
          const acquiredLock: AcquiredLock = {
            key: lockKey,
            token,
            ttl,
            acquiredAt: new Date()
          };

          this.logger.debug(`Lock acquired: ${lockKey} with token: ${token}`);
          return acquiredLock;
        }

        // 락 획득 실패시 재시도
        if (attempt < retryCount) {
          this.logger.debug(`Lock acquisition failed for ${lockKey}, retrying in ${retryDelay}ms...`);
          await this.sleep(retryDelay);
        }

      } catch (error) {
        this.logger.error(`Error acquiring lock ${lockKey}:`, error);
        if (attempt < retryCount) {
          await this.sleep(retryDelay);
        }
      }
    }

    this.logger.warn(`Failed to acquire lock: ${lockKey} after ${retryCount} attempts`);
    return null;
  }

  /**
   * 분산락 해제
   * @param lock 해제할 락
   * @returns 성공시 true, 실패시 false
   */
  async releaseLock(lock: AcquiredLock): Promise<boolean> {
    try {
      // Lua 스크립트를 사용하여 안전하게 해제 (토큰 검증)
      const result = await this.redis.eval(
        this.unlockScript,
        1,
        lock.key,
        lock.token
      ) as number;

      if (result === 1) {
        this.logger.debug(`Lock released: ${lock.key}`);
        return true;
      } else {
        this.logger.warn(`Lock not released (token mismatch or expired): ${lock.key}`);
        return false;
      }
    } catch (error) {
      this.logger.error(`Error releasing lock ${lock.key}:`, error);
      return false;
    }
  }

  /**
   * 락 갱신 (TTL 연장)
   * @param lock 갱신할 락
   * @param ttl 새로운 TTL (milliseconds)
   * @returns 성공시 true, 실패시 false
   */
  async renewLock(lock: AcquiredLock, ttl: number): Promise<boolean> {
    try {
      const result = await this.redis.eval(
        this.renewScript,
        1,
        lock.key,
        lock.token,
        ttl.toString()
      ) as number;

      if (result === 1) {
        lock.ttl = ttl;
        this.logger.debug(`Lock renewed: ${lock.key} for ${ttl}ms`);
        return true;
      } else {
        this.logger.warn(`Lock renewal failed (token mismatch or expired): ${lock.key}`);
        return false;
      }
    } catch (error) {
      this.logger.error(`Error renewing lock ${lock.key}:`, error);
      return false;
    }
  }

  /**
   * 락 상태 확인
   * @param key 확인할 락 키
   * @returns 락이 존재하면 true, 없으면 false
   */
  async isLocked(key: string): Promise<boolean> {
    try {
      const lockKey = `lock:${key}`;
      const exists = await this.redis.exists(lockKey);
      return exists === 1;
    } catch (error) {
      this.logger.error(`Error checking lock status ${key}:`, error);
      return false;
    }
  }

  /**
   * 락과 함께 실행 (자동 해제)
   * @param key 락 키
   * @param fn 실행할 함수
   * @param options 락 옵션
   * @returns 함수 실행 결과
   */
  async withLock<T>(
    key: string,
    fn: () => Promise<T>,
    options: LockOptions = {}
  ): Promise<T> {
    const lock = await this.acquireLock(key, options);
    
    if (!lock) {
      throw new Error(`Failed to acquire lock: ${key}`);
    }

    try {
      const result = await fn();
      return result;
    } finally {
      await this.releaseLock(lock);
    }
  }

  /**
   * 유니크 토큰 생성
   */
  private generateToken(): string {
    return `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  }

  /**
   * 슬립 함수
   */
  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * 서비스 종료시 Redis 연결 해제
   */
  async onModuleDestroy() {
    await this.redis.quit();
    this.logger.log('Redis connection closed');
  }
} 