import { Module } from '@nestjs/common';
import { CqrsModule } from '@nestjs/cqrs';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Payment } from './entities/payment.entity';
import { EventStore } from '../event-store/entities/event-store.entity';

// Command Handlers
import {
  ProcessPaymentHandler,
  RefundPaymentHandler,
} from './commands/handlers/payment.handlers';

// Event Handlers
import {
  PaymentProcessedHandler,
  PaymentFailedHandler,
  PaymentRefundedHandler,
} from './events/handlers/payment.handlers';

const CommandHandlers = [
  ProcessPaymentHandler,
  RefundPaymentHandler,
];

const EventHandlers = [
  PaymentProcessedHandler,
  PaymentFailedHandler,
  PaymentRefundedHandler,
];

@Module({
  imports: [
    CqrsModule,
    TypeOrmModule.forFeature([Payment, EventStore]),
  ],
  providers: [
    ...CommandHandlers,
    ...EventHandlers,
  ],
  exports: [
    ...CommandHandlers,
    ...EventHandlers,
  ],
})
export class PaymentModule {}