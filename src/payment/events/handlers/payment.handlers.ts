import { EventsHandler, IEventHandler } from '@nestjs/cqrs';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { PaymentProcessedEvent, PaymentFailedEvent, PaymentRefundedEvent } from '../payment.events';
import { EventStore } from 'src/event-store/entities/event-store.entity';
import { Logger } from '@nestjs/common';
import { KafkaService } from 'src/kafka/kafka.service';

@EventsHandler(PaymentProcessedEvent)
export class PaymentProcessedHandler implements IEventHandler<PaymentProcessedEvent> {
  private readonly logger = new Logger(PaymentProcessedHandler.name);

  constructor(
    @InjectRepository(EventStore)
    private readonly eventStoreRepository: Repository<EventStore>,
    private readonly kafkaService: KafkaService,
  ) {}

  async handle(event: PaymentProcessedEvent) {
    this.logger.log(`Payment processed: ${event.paymentId}`);

    // 이벤트 스토어에 저장
    const eventStoreEntry = this.eventStoreRepository.create({
      aggregateId: event.paymentId,
      aggregateType: 'Payment',
      eventType: 'PaymentProcessed',
      eventData: {
        paymentId: event.paymentId,
        orderId: event.orderId,
        userId: event.userId,
        amount: event.amount,
        externalTransactionId: event.externalTransactionId,
      },
      correlationId: event.correlationId,
      occurredAt: event.occurredAt,
    });

    await this.eventStoreRepository.save(eventStoreEntry);

    // Kafka로 이벤트 발행
    await this.kafkaService.publish('payment-events', {
      type: 'PaymentProcessed',
      ...event,
    });

    // Saga는 이벤트를 자동으로 수신하여 처리함
    this.logger.log(`PaymentProcessed event published for correlation: ${event.correlationId}`);
  }
}

@EventsHandler(PaymentFailedEvent)
export class PaymentFailedHandler implements IEventHandler<PaymentFailedEvent> {
  private readonly logger = new Logger(PaymentFailedHandler.name);

  constructor(
    @InjectRepository(EventStore)
    private readonly eventStoreRepository: Repository<EventStore>,
    private readonly kafkaService: KafkaService,
  ) {}

  async handle(event: PaymentFailedEvent) {
    this.logger.log(`Payment failed: ${event.paymentId}`);

    const eventStoreEntry = this.eventStoreRepository.create({
      aggregateId: event.paymentId,
      aggregateType: 'Payment',
      eventType: 'PaymentFailed',
      eventData: {
        paymentId: event.paymentId,
        orderId: event.orderId,
        userId: event.userId,
        amount: event.amount,
        failureReason: event.failureReason,
      },
      correlationId: event.correlationId,
      occurredAt: event.occurredAt,
    });

    await this.eventStoreRepository.save(eventStoreEntry);

    // Kafka로 이벤트 발행
    await this.kafkaService.publish('payment-events', {
      type: 'PaymentFailed',
      ...event,
    });

    // Saga는 이벤트를 자동으로 수신하여 보상 트랜잭션 시작
    this.logger.log(`PaymentFailed event published for correlation: ${event.correlationId}`);
  }
}

@EventsHandler(PaymentRefundedEvent)
export class PaymentRefundedHandler implements IEventHandler<PaymentRefundedEvent> {
  private readonly logger = new Logger(PaymentRefundedHandler.name);

  constructor(
    @InjectRepository(EventStore)
    private readonly eventStoreRepository: Repository<EventStore>,
    private readonly kafkaService: KafkaService,
  ) {}

  async handle(event: PaymentRefundedEvent) {
    this.logger.log(`Payment refunded: ${event.paymentId}`);

    const eventStoreEntry = this.eventStoreRepository.create({
      aggregateId: event.paymentId,
      aggregateType: 'Payment',
      eventType: 'PaymentRefunded',
      eventData: {
        paymentId: event.paymentId,
        orderId: event.orderId,
        refundAmount: event.refundAmount,
        reason: event.reason,
      },
      correlationId: event.correlationId,
      occurredAt: event.occurredAt,
    });

    await this.eventStoreRepository.save(eventStoreEntry);

    // Kafka로 이벤트 발행
    await this.kafkaService.publish('payment-events', {
      type: 'PaymentRefunded',
      ...event,
    });
  }
}