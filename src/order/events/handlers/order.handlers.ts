import { EventsHandler, IEventHandler } from '@nestjs/cqrs';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { 
  OrderCreatedEvent, 
  OrderCancelledEvent, 
  OrderConfirmedEvent,
  OrderStatusChangedEvent 
} from '../order.events';
import { EventStore } from 'src/event-store/entities/event-store.entity';
import { Logger } from '@nestjs/common';
import { KafkaService } from 'src/kafka/kafka.service';
import { OrderProcessingSaga } from 'src/saga/order-processing.saga';

@EventsHandler(OrderCreatedEvent)
export class OrderCreatedHandler implements IEventHandler<OrderCreatedEvent> {
  private readonly logger = new Logger(OrderCreatedHandler.name);

  constructor(
    @InjectRepository(EventStore)
    private readonly eventStoreRepository: Repository<EventStore>,
    private readonly kafkaService: KafkaService,
    private readonly orderProcessingSaga: OrderProcessingSaga,
  ) {}

  async handle(event: OrderCreatedEvent) {
    this.logger.log(`Order created: ${event.orderId}`);

    // 이벤트 스토어에 저장
    const eventStoreEntry = this.eventStoreRepository.create({
      aggregateId: event.orderId,
      aggregateType: 'Order',
      eventType: 'OrderCreated',
      eventData: {
        orderId: event.orderId,
        userId: event.userId,
        totalAmount: event.totalAmount,
        items: event.items,
        shippingAddress: event.shippingAddress,
      },
      correlationId: event.correlationId,
      occurredAt: event.occurredAt,
    });

    await this.eventStoreRepository.save(eventStoreEntry);

    // Kafka로 이벤트 발행
    await this.kafkaService.publish('order-events', {
      type: 'OrderCreated',
      ...event,
    });

    // Saga 시작
    await this.orderProcessingSaga.handleOrderCreated(event);
  }
}

@EventsHandler(OrderCancelledEvent)
export class OrderCancelledHandler implements IEventHandler<OrderCancelledEvent> {
  private readonly logger = new Logger(OrderCancelledHandler.name);

  constructor(
    @InjectRepository(EventStore)
    private readonly eventStoreRepository: Repository<EventStore>,
    private readonly kafkaService: KafkaService,
  ) {}

  async handle(event: OrderCancelledEvent) {
    this.logger.log(`Order cancelled: ${event.orderId}`);

    const eventStoreEntry = this.eventStoreRepository.create({
      aggregateId: event.orderId,
      aggregateType: 'Order',
      eventType: 'OrderCancelled',
      eventData: {
        orderId: event.orderId,
        userId: event.userId,
        reason: event.reason,
      },
      correlationId: event.correlationId,
      occurredAt: event.occurredAt,
    });

    await this.eventStoreRepository.save(eventStoreEntry);

    // Kafka로 이벤트 발행
    await this.kafkaService.publish('order-events', {
      type: 'OrderCancelled',
      ...event,
    });
  }
}

@EventsHandler(OrderConfirmedEvent)
export class OrderConfirmedHandler implements IEventHandler<OrderConfirmedEvent> {
  private readonly logger = new Logger(OrderConfirmedHandler.name);

  constructor(
    @InjectRepository(EventStore)
    private readonly eventStoreRepository: Repository<EventStore>,
    private readonly kafkaService: KafkaService,
  ) {}

  async handle(event: OrderConfirmedEvent) {
    this.logger.log(`Order confirmed: ${event.orderId}`);

    const eventStoreEntry = this.eventStoreRepository.create({
      aggregateId: event.orderId,
      aggregateType: 'Order',
      eventType: 'OrderConfirmed',
      eventData: {
        orderId: event.orderId,
        paymentId: event.paymentId,
        totalAmount: event.totalAmount,
      },
      correlationId: event.correlationId,
      occurredAt: event.occurredAt,
    });

    await this.eventStoreRepository.save(eventStoreEntry);

    // Kafka로 이벤트 발행
    await this.kafkaService.publish('order-events', {
      type: 'OrderConfirmed',
      ...event,
    });
  }
}

@EventsHandler(OrderStatusChangedEvent)
export class OrderStatusChangedHandler implements IEventHandler<OrderStatusChangedEvent> {
  private readonly logger = new Logger(OrderStatusChangedHandler.name);

  constructor(
    @InjectRepository(EventStore)
    private readonly eventStoreRepository: Repository<EventStore>,
    private readonly kafkaService: KafkaService,
  ) {}

  async handle(event: OrderStatusChangedEvent) {
    this.logger.log(`Order status changed: ${event.orderId} from ${event.previousStatus} to ${event.newStatus}`);

    const eventStoreEntry = this.eventStoreRepository.create({
      aggregateId: event.orderId,
      aggregateType: 'Order',
      eventType: 'OrderStatusChanged',
      eventData: {
        orderId: event.orderId,
        previousStatus: event.previousStatus,
        newStatus: event.newStatus,
      },
      correlationId: event.correlationId,
      occurredAt: event.occurredAt,
    });

    await this.eventStoreRepository.save(eventStoreEntry);

    // Kafka로 이벤트 발행
    await this.kafkaService.publish('order-events', {
      type: 'OrderStatusChanged',
      ...event,
    });
  }
}