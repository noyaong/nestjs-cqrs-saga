import { Module } from '@nestjs/common';
import { CqrsModule } from '@nestjs/cqrs';
import { TypeOrmModule } from '@nestjs/typeorm';
import { SagaInstance } from './entities/saga-instance.entity';
import { Order } from '../order/entities/order.entity';
import { Payment } from '../payment/entities/payment.entity';
import { SagaManager } from './saga-manager.service';
import { 
  OrderProcessingSaga, 
  PaymentProcessedSagaHandler, 
  PaymentFailedSagaHandler 
} from './order-processing.saga';
import { SagaController } from './saga.controller';
import { SagaMaintenanceController } from './saga-maintenance.controller';
import { RedisModule } from '../redis/redis.module';

@Module({
  imports: [
    CqrsModule,
    TypeOrmModule.forFeature([SagaInstance, Order, Payment]),
    RedisModule,
  ],
  controllers: [SagaController, SagaMaintenanceController],
  providers: [
    SagaManager, 
    OrderProcessingSaga,
    PaymentProcessedSagaHandler,
    PaymentFailedSagaHandler,
  ],
  exports: [SagaManager, OrderProcessingSaga],
})
export class SagaModule {}