import { registerAs } from '@nestjs/config';
import { TypeOrmModuleOptions } from '@nestjs/typeorm';

export const databaseConfig = registerAs(
  'database',
  (): TypeOrmModuleOptions => ({
    type: 'postgres',
    host: process.env.DATABASE_HOST || 'localhost',
    port: parseInt(process.env.DATABASE_PORT, 10) || 5432,
    username: process.env.DATABASE_USER || 'postgres',
    password: process.env.DATABASE_PASSWORD || 'postgres123',
    database: process.env.DATABASE_NAME || 'nestjs_cqrs',
    entities: [__dirname + '/../**/*.entity.js'],
    migrations: [__dirname + '/../migrations/*{.ts,.js}'],
    synchronize: true, // 개발 환경에서 Entity 변경사항 자동 반영
    logging: process.env.NODE_ENV === 'development',
    ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
    
    // Connection Pool 설정
    extra: {
      connectionLimit: 20, // 최대 연결 수
      acquireTimeout: 60000, // 연결 획득 대기 시간 (60초)
      timeout: 60000, // 쿼리 타임아웃 (60초)
      reconnect: true,
      pool: {
        min: 5, // 최소 연결 수
        max: 20, // 최대 연결 수
        acquireTimeoutMillis: 60000, // 연결 획득 대기 시간
        createTimeoutMillis: 30000, // 연결 생성 대기 시간
        destroyTimeoutMillis: 5000, // 연결 종료 대기 시간
        idleTimeoutMillis: 30000, // 비활성 연결 제거 시간
        reapIntervalMillis: 1000, // 연결 정리 반복 주기
      },
    },
  }),
);