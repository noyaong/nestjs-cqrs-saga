import { CommandHandler, ICommandHandler, EventBus } from '@nestjs/cqrs';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Payment, PaymentStatus } from '../../entities/payment.entity';
import { ProcessPaymentCommand, RefundPaymentCommand } from '../payment.commands';
import { PaymentProcessedEvent, PaymentFailedEvent, PaymentRefundedEvent } from '../../events/payment.events';
import { Logger } from '@nestjs/common';
import { v4 as uuidv4 } from 'uuid';

@CommandHandler(ProcessPaymentCommand)
export class ProcessPaymentHandler implements ICommandHandler<ProcessPaymentCommand> {
  private readonly logger = new Logger(ProcessPaymentHandler.name);

  constructor(
    @InjectRepository(Payment)
    private readonly paymentRepository: Repository<Payment>,
    private readonly eventBus: EventBus,
  ) {}

  async execute(command: ProcessPaymentCommand): Promise<Payment> {
    const { orderId, userId, amount, method, correlationId } = command;

    this.logger.log(`Processing payment for order: ${orderId}, amount: ${amount}`);

    // 결제 레코드 생성
    const payment = this.paymentRepository.create({
      orderId,
      userId,
      amount,
      method,
      status: PaymentStatus.PROCESSING,
    });

    const savedPayment = await this.paymentRepository.save(payment);

    // 외부 결제 시스템 시뮬레이션
    await this.simulateExternalPaymentProcessing(savedPayment, correlationId);

    return savedPayment;
  }

  private async simulateExternalPaymentProcessing(payment: Payment, correlationId: string) {
    // 실제로는 외부 결제 API 호출
    // 여기서는 시뮬레이션으로 랜덤 성공/실패
    
    // 비동기로 처리하여 커넥션 블로킹 방지
    setImmediate(async () => {
      try {
        // 랜덤 지연 (0.5초 ~ 2초)
        const delay = Math.random() * 1500 + 500;
        await new Promise(resolve => setTimeout(resolve, delay));
        
        const isSuccess = Math.random() > 0.2; // 80% 성공률
        
        if (isSuccess) {
          // 결제 성공
          payment.status = PaymentStatus.COMPLETED;
          payment.externalTransactionId = `ext_tx_${uuidv4()}`;
          
          await this.paymentRepository.save(payment);
          
          const event = new PaymentProcessedEvent(
            payment.id,
            payment.orderId,
            payment.userId,
            payment.amount,
            payment.externalTransactionId,
            correlationId,
          );
          
          this.eventBus.publish(event);
          this.logger.log(`Payment processed successfully: ${payment.id}`);
          
        } else {
          // 결제 실패
          payment.status = PaymentStatus.FAILED;
          payment.failureReason = 'Insufficient funds or card declined';
          
          await this.paymentRepository.save(payment);
          
          const event = new PaymentFailedEvent(
            payment.id,
            payment.orderId,
            payment.userId,
            payment.amount,
            payment.failureReason,
            correlationId,
          );
          
          this.eventBus.publish(event);
          this.logger.log(`Payment failed: ${payment.id} - ${payment.failureReason}`);
        }
      } catch (error) {
        this.logger.error(`Error in payment processing: ${payment.id}`, error);
        
        // 에러 발생 시 실패 처리
        payment.status = PaymentStatus.FAILED;
        payment.failureReason = 'Payment processing error';
        await this.paymentRepository.save(payment);
        
        const event = new PaymentFailedEvent(
          payment.id,
          payment.orderId,
          payment.userId,
          payment.amount,
          payment.failureReason,
          correlationId,
        );
        
        this.eventBus.publish(event);
      }
    });
  }
}

@CommandHandler(RefundPaymentCommand)
export class RefundPaymentHandler implements ICommandHandler<RefundPaymentCommand> {
  private readonly logger = new Logger(RefundPaymentHandler.name);

  constructor(
    @InjectRepository(Payment)
    private readonly paymentRepository: Repository<Payment>,
    private readonly eventBus: EventBus,
  ) {}

  async execute(command: RefundPaymentCommand): Promise<void> {
    const { paymentId, reason, correlationId } = command;

    const payment = await this.paymentRepository.findOne({
      where: { id: paymentId },
    });

    if (!payment || payment.status !== PaymentStatus.COMPLETED) {
      throw new Error('Payment not found or cannot be refunded');
    }

    payment.status = PaymentStatus.REFUNDED;
    await this.paymentRepository.save(payment);

    const event = new PaymentRefundedEvent(
      paymentId,
      payment.orderId,
      payment.amount,
      reason,
      correlationId,
    );

    this.eventBus.publish(event);
    this.logger.log(`Payment refunded: ${paymentId}`);
  }
}