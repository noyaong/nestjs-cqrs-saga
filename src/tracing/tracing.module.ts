import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { TracingController } from './tracing.controller';
import { SagaInstance } from '../saga/entities/saga-instance.entity';
import { Order } from '../order/entities/order.entity';
import { Payment } from '../payment/entities/payment.entity';
import { EventStore } from '../event-store/entities/event-store.entity';

@Module({
  imports: [
    TypeOrmModule.forFeature([SagaInstance, Order, Payment, EventStore]),
  ],
  controllers: [TracingController],
})
export class TracingModule {}