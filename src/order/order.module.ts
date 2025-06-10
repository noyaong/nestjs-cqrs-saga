import { Module } from '@nestjs/common';
import { CqrsModule } from '@nestjs/cqrs';
import { TypeOrmModule } from '@nestjs/typeorm';
import { OrderController } from './order.controller';
import { Order } from './entities/order.entity';
import { EventStore } from 'src/event-store/entities/event-store.entity';
import { SagaModule } from '../saga/saga.module';

// Command Handlers
import {
  CreateOrderHandler,
  CancelOrderHandler,
  ConfirmOrderHandler,
} from './commands/handlers/order.handlers';

// Query Handlers
import {
  GetOrderByIdHandler,
  GetOrdersByUserIdHandler,
  GetOrdersHandler,
} from './queries/handlers/order.handlers';

// Event Handlers
import {
  OrderCreatedHandler,
  OrderCancelledHandler,
  OrderConfirmedHandler,
  OrderStatusChangedHandler,
} from './events/handlers/order.handlers';

const CommandHandlers = [
  CreateOrderHandler,
  CancelOrderHandler,
  ConfirmOrderHandler,
];

const QueryHandlers = [
  GetOrderByIdHandler,
  GetOrdersByUserIdHandler,
  GetOrdersHandler,
];

const EventHandlers = [
  OrderCreatedHandler,
  OrderCancelledHandler,
  OrderConfirmedHandler,
  OrderStatusChangedHandler,
];

@Module({
  imports: [
    CqrsModule,
    TypeOrmModule.forFeature([Order, EventStore]),
    SagaModule,
  ],
  controllers: [OrderController],
  providers: [
    ...CommandHandlers,
    ...QueryHandlers,
    ...EventHandlers,
  ],
  exports: [
    ...CommandHandlers,
    ...QueryHandlers,
    ...EventHandlers,
  ],
})
export class OrderModule {}