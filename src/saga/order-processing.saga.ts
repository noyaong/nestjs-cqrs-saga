import { Injectable, Logger } from '@nestjs/common';
import { EventsHandler, IEventHandler, CommandBus } from '@nestjs/cqrs';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { SagaInstance, SagaStatus } from './entities/saga-instance.entity';
import { SagaManager } from './saga-manager.service';
import { OrderCreatedEvent } from '../order/events/order.events';
import { PaymentProcessedEvent, PaymentFailedEvent } from '../payment/events/payment.events';
import { ProcessPaymentCommand } from '../payment/commands/payment.commands';
import { ConfirmOrderCommand, CancelOrderCommand } from '../order/commands/order.commands';
import { PaymentMethod } from '../payment/entities/payment.entity';
import { v4 as uuidv4 } from 'uuid';

@Injectable()
export class OrderProcessingSaga {
  private readonly logger = new Logger(OrderProcessingSaga.name);

  constructor(
    @InjectRepository(SagaInstance)
    private readonly sagaRepository: Repository<SagaInstance>,
    private readonly commandBus: CommandBus,
    private readonly sagaManager: SagaManager,
  ) {}

  async handleOrderCreated(event: OrderCreatedEvent): Promise<void> {
    this.logger.log(`Starting Order Processing Saga for order: ${event.orderId}`);

    const correlationId = event.correlationId;
    
    if (!correlationId) {
      this.logger.error(`Missing correlationId in OrderCreatedEvent for order: ${event.orderId}`);
      return;
    }

    // Saga 시작
    const saga = await this.sagaManager.startSaga(
      'OrderProcessingSaga',
      correlationId,
      {
        orderId: event.orderId,
        userId: event.userId,
        totalAmount: event.totalAmount,
        items: event.items,
        shippingAddress: event.shippingAddress,
      },
      [], // steps는 동적으로 실행
    );

    // 첫 번째 단계: 결제 처리
    await this.executePaymentStep(saga, event);
  }

  private async executePaymentStep(saga: SagaInstance, event: OrderCreatedEvent): Promise<void> {
    await this.sagaManager.executeSagaStep(
      saga.id,
      'payment_processing',
      async () => {
        const paymentCommand = new ProcessPaymentCommand(
          event.orderId,
          event.userId,
          event.totalAmount,
          PaymentMethod.CREDIT_CARD,
          saga.correlationId,
        );

        await this.commandBus.execute(paymentCommand);
        this.logger.log(`Payment command executed for saga: ${saga.id}`);
      }
    );
  }

  async handlePaymentProcessed(event: PaymentProcessedEvent): Promise<void> {
    this.logger.log(`Payment processed for correlation ID: ${event.correlationId}`);

    const saga = await this.sagaManager.findSagaByCorrelationId(
      event.correlationId,
      'OrderProcessingSaga'
    );

    if (!saga) {
      this.logger.warn(`Saga not found for correlation ID: ${event.correlationId}`);
      return;
    }

    // 두 번째 단계: 주문 확인
    await this.executeOrderConfirmationStep(saga, event);
  }

  private async executeOrderConfirmationStep(
    saga: SagaInstance,
    event: PaymentProcessedEvent
  ): Promise<void> {
    await this.sagaManager.executeSagaStep(
      saga.id,
      'order_confirmation',
      async () => {
        const confirmCommand = new ConfirmOrderCommand(
          event.orderId,
          event.paymentId,
          saga.correlationId,
        );

        await this.commandBus.execute(confirmCommand);
        this.logger.log(`Order confirmation command executed for saga: ${saga.id}`);
      }
    );

    // 주문 확인 완료 후 Saga 완료
    await this.sagaManager.completeSaga(saga.id);
  }

  async handlePaymentFailed(event: PaymentFailedEvent): Promise<void> {
    this.logger.log(`Payment failed for correlation ID: ${event.correlationId}`);

    const saga = await this.sagaManager.findSagaByCorrelationId(
      event.correlationId,
      'OrderProcessingSaga'
    );

    if (!saga) {
      this.logger.warn(`Saga not found for correlation ID: ${event.correlationId}`);
      return;
    }

    // 보상 트랜잭션: 주문 취소
    await this.executeOrderCancellationStep(saga, event);
  }

  private async executeOrderCancellationStep(
    saga: SagaInstance,
    event: PaymentFailedEvent
  ): Promise<void> {
    try {
      this.logger.log(`Executing compensation for saga: ${saga.id}`);

      const cancelCommand = new CancelOrderCommand(
        event.orderId,
        event.userId,
        `Payment failed: ${event.failureReason}`,
        saga.correlationId,
      );

      await this.commandBus.execute(cancelCommand);
      this.logger.log(`Order cancellation executed for saga: ${saga.id}`);

      // 보상 완료 상태로 업데이트
      saga.status = SagaStatus.COMPENSATED;
      saga.compensationSteps.push('order_cancelled');
      saga.currentStep = 'compensated';
      await this.sagaRepository.save(saga);

      this.logger.log(`Saga compensation completed: ${saga.id}`);

    } catch (error) {
      this.logger.error(`Saga compensation failed for saga: ${saga.id}`, error);
      await this.sagaManager.handleSagaFailure(
        saga,
        'order_cancellation',
        error.message
      );
    }
  }

  // Saga 상태 조회 메서드들
  async getSagaStatus(correlationId: string): Promise<SagaInstance | null> {
    return this.sagaManager.findSagaByCorrelationId(correlationId, 'OrderProcessingSaga');
  }

  async getAllOrderSagas(): Promise<SagaInstance[]> {
    return this.sagaRepository.find({
      where: { sagaType: 'OrderProcessingSaga' },
      order: { createdAt: 'DESC' },
    });
  }
}

// Event Handler들을 별도로 분리
@EventsHandler(PaymentProcessedEvent)
export class PaymentProcessedSagaHandler implements IEventHandler<PaymentProcessedEvent> {
  private readonly logger = new Logger(PaymentProcessedSagaHandler.name);

  constructor(private readonly orderProcessingSaga: OrderProcessingSaga) {}

  async handle(event: PaymentProcessedEvent) {
    this.logger.log(`Handling PaymentProcessed for Saga: ${event.correlationId}`);
    await this.orderProcessingSaga.handlePaymentProcessed(event);
  }
}

@EventsHandler(PaymentFailedEvent)
export class PaymentFailedSagaHandler implements IEventHandler<PaymentFailedEvent> {
  private readonly logger = new Logger(PaymentFailedSagaHandler.name);

  constructor(private readonly orderProcessingSaga: OrderProcessingSaga) {}

  async handle(event: PaymentFailedEvent) {
    this.logger.log(`Handling PaymentFailed for Saga: ${event.correlationId}`);
    await this.orderProcessingSaga.handlePaymentFailed(event);
  }
}