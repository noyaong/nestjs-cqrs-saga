import { Controller, Post, Body, Get, Param } from '@nestjs/common';
import { ApiTags, ApiOperation } from '@nestjs/swagger';
import { RedisLockService } from './redis-lock.service';
import { Logger } from '@nestjs/common';

@ApiTags('Redis Distributed Lock Test')
@Controller('redis-test')
export class RedisTestController {
  private readonly logger = new Logger(RedisTestController.name);

  constructor(private readonly redisLockService: RedisLockService) {}

  @Post('lock/:key')
  @ApiOperation({ summary: '분산락 테스트 - 동시 실행 테스트' })
  async testDistributedLock(
    @Param('key') key: string,
    @Body() body: { duration?: number; nodeId?: string }
  ) {
    const { duration = 5000, nodeId = 'node-1' } = body;
    const startTime = Date.now();

    this.logger.log(`[${nodeId}] Attempting to acquire lock: ${key}`);

    try {
      const result = await this.redisLockService.withLock(
        key,
        async () => {
          this.logger.log(`[${nodeId}] 🔒 Lock acquired! Working for ${duration}ms...`);
          
          // 시뮬레이션: 중요한 작업 수행
          await new Promise(resolve => setTimeout(resolve, duration));
          
          this.logger.log(`[${nodeId}] ✅ Work completed!`);
          
          return {
            nodeId,
            message: `Critical section executed by ${nodeId}`,
            workDuration: duration,
            executedAt: new Date().toISOString()
          };
        },
        {
          ttl: 30000, // 30초
          retryCount: 5,
          retryDelay: 500,
        }
      );

      const totalTime = Date.now() - startTime;
      
      return {
        success: true,
        result,
        totalTime,
        message: `Lock acquired and released successfully by ${nodeId}`
      };

    } catch (error) {
      const totalTime = Date.now() - startTime;
      
      this.logger.error(`[${nodeId}] ❌ Failed to acquire lock: ${error.message}`);
      
      return {
        success: false,
        error: error.message,
        totalTime,
        nodeId,
        message: `Failed to acquire lock for ${key}`
      };
    }
  }

  @Post('saga-creation-test')
  @ApiOperation({ summary: 'Saga 생성 중복 방지 테스트' })
  async testSagaCreation(@Body() body: { correlationId: string; nodeId?: string }) {
    const { correlationId, nodeId = 'node-1' } = body;
    const lockKey = `saga_creation:OrderProcessingSaga:${correlationId}`;

    this.logger.log(`[${nodeId}] Testing Saga creation lock for: ${correlationId}`);

    try {
      const result = await this.redisLockService.withLock(
        lockKey,
        async () => {
          this.logger.log(`[${nodeId}] 🔒 Saga creation lock acquired!`);
          
          // Saga 생성 시뮬레이션
          await new Promise(resolve => setTimeout(resolve, 2000));
          
          const sagaId = `saga_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
          
          this.logger.log(`[${nodeId}] ✅ Saga created: ${sagaId}`);
          
          return {
            sagaId,
            correlationId,
            createdBy: nodeId,
            createdAt: new Date().toISOString()
          };
        },
        {
          ttl: 30000,
          retryCount: 3,
          retryDelay: 100,
        }
      );

      return {
        success: true,
        result,
        message: `Saga creation protected by distributed lock`
      };

    } catch (error) {
      this.logger.error(`[${nodeId}] ❌ Saga creation failed: ${error.message}`);
      
      return {
        success: false,
        error: error.message,
        nodeId,
        correlationId
      };
    }
  }

  @Get('lock-status/:key')
  @ApiOperation({ summary: '락 상태 확인' })
  async checkLockStatus(@Param('key') key: string) {
    const isLocked = await this.redisLockService.isLocked(key);
    
    return {
      key,
      isLocked,
      checkedAt: new Date().toISOString()
    };
  }

  @Post('manual-lock/:key')
  @ApiOperation({ summary: '수동 락 획득/해제 테스트' })
  async manualLockTest(@Param('key') key: string) {
    this.logger.log(`Manual lock test for key: ${key}`);

    // 1. 락 획득
    const lock = await this.redisLockService.acquireLock(key, {
      ttl: 10000, // 10초
      retryCount: 2
    });

    if (!lock) {
      return {
        success: false,
        message: 'Failed to acquire lock'
      };
    }

    this.logger.log(`Lock acquired: ${lock.key} with token: ${lock.token}`);

    // 2. 5초 대기
    await new Promise(resolve => setTimeout(resolve, 5000));

    // 3. 락 갱신
    const renewed = await this.redisLockService.renewLock(lock, 15000);
    this.logger.log(`Lock renewal: ${renewed}`);

    // 4. 3초 더 대기
    await new Promise(resolve => setTimeout(resolve, 3000));

    // 5. 락 해제
    const released = await this.redisLockService.releaseLock(lock);
    this.logger.log(`Lock released: ${released}`);

    return {
      success: true,
      lockInfo: {
        key: lock.key,
        token: lock.token,
        ttl: lock.ttl,
        acquiredAt: lock.acquiredAt
      },
      operations: {
        acquired: true,
        renewed,
        released
      }
    };
  }
} 