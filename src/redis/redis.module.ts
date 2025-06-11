import { Module } from '@nestjs/common';
import { RedisLockService } from './redis-lock.service';
import { RedisTestController } from './redis-test.controller';

@Module({
  controllers: [RedisTestController],
  providers: [RedisLockService],
  exports: [RedisLockService],
})
export class RedisModule {} 