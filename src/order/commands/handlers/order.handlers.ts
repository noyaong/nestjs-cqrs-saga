import { CommandHandler, ICommandHandler, EventBus } from '@nestjs/cqrs';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Order, OrderStatus } from '../../entities/order.entity';
import { CreateOrderCommand, CancelOrderCommand, ConfirmOrderCommand } from '../order.commands';
import { 
  OrderCreatedEvent, 
  OrderCancelledEvent, 
  OrderConfirmedEvent,
  OrderStatusChangedEvent 
} from '../../events/order.events';
import { ConflictException, NotFoundException, Logger } from '@nestjs/common';
import { v4 as uuidv4 } from 'uuid';

// 중복 Order 예외 클래스
export class DuplicateOrderException extends ConflictException {
  constructor(existingOrderId: string, idempotencyKey: string) {
    super({
      message: 'Order with this product combination already exists',
      error: 'DUPLICATE_ORDER',
      existingOrderId,
      idempotencyKey,
      code: 'ORDER_ALREADY_EXISTS'
    });
  }
}

@CommandHandler(CreateOrderCommand)
export class CreateOrderHandler implements ICommandHandler<CreateOrderCommand> {
  private readonly logger = new Logger(CreateOrderHandler.name);

  constructor(
    @InjectRepository(Order)
    private readonly orderRepository: Repository<Order>,
    private readonly eventBus: EventBus,
  ) {}

  async execute(command: CreateOrderCommand): Promise<Order> {
    const { userId, items, shippingAddress, correlationId } = command;

    this.logger.debug(`🔍 DEBUG Handler: received correlationId = ${correlationId}`);

    try {
      // correlationId가 있다면 기존 주문 확인 (중복 방지)
      if (correlationId) {
        const existingOrder = await this.orderRepository.findOne({
          where: { idempotencyKey: correlationId }
        });

        if (existingOrder) {
          this.logger.log(`⚠️ Duplicate order detected with idempotencyKey: ${correlationId}, existing order: ${existingOrder.id}`);
          throw new DuplicateOrderException(existingOrder.id, correlationId);
        }
      }

      // 총 금액 계산
      const totalAmount = items.reduce((sum, item) => sum + (item.price * item.quantity), 0);

      // 단순한 트랜잭션으로 주문 생성 (queryRunner 사용하지 않음)
      const order = this.orderRepository.create({
        userId,
        totalAmount,
        items,
        shippingAddress,
        status: OrderStatus.PENDING,
        idempotencyKey: correlationId,
      });

      const savedOrder = await this.orderRepository.save(order);
      
      this.logger.log(`📦 Order created successfully: ${savedOrder.id}`);

      // 이벤트 발행 (트랜잭션 외부에서)
      const event = new OrderCreatedEvent(
        savedOrder.id,
        savedOrder.userId,
        savedOrder.totalAmount,
        savedOrder.items,
        savedOrder.shippingAddress,
        correlationId, // correlationId를 그대로 사용 (null이면 Saga에서 처리)
      );

      // 비동기로 이벤트 발행 (연결 블로킹 방지)
      setImmediate(() => {
        this.eventBus.publish(event);
      });

      return savedOrder;
      
    } catch (error) {
      // DB 유니크 제약조건 위반 시 Conflict 예외
      if (error.code === '23505' && error.detail?.includes('idempotencyKey')) {
        this.logger.log(`⚠️ Database constraint violation - duplicate idempotencyKey: ${correlationId}`);
        const existingOrder = await this.orderRepository.findOne({
          where: { idempotencyKey: correlationId }
        });
        
        if (existingOrder) {
          throw new DuplicateOrderException(existingOrder.id, correlationId);
        }
      }
      
      this.logger.error(`❌ Failed to create order for user ${userId}:`, error);
      throw error;
    }
  }
}

@CommandHandler(CancelOrderCommand)
export class CancelOrderHandler implements ICommandHandler<CancelOrderCommand> {
  private readonly logger = new Logger(CancelOrderHandler.name);

  constructor(
    @InjectRepository(Order)
    private readonly orderRepository: Repository<Order>,
    private readonly eventBus: EventBus,
  ) {}

  async execute(command: CancelOrderCommand): Promise<void> {
    const { orderId, userId, reason, correlationId } = command;

    try {
      const order = await this.orderRepository.findOne({
        where: { id: orderId, userId },
      });

      if (!order) {
        throw new NotFoundException('Order not found');
      }

      if (order.status === OrderStatus.CANCELLED) {
        this.logger.warn(`Order already cancelled: ${orderId}`);
        return;
      }

      if (order.status === OrderStatus.DELIVERED) {
        throw new ConflictException('Cannot cancel delivered order');
      }

      const previousStatus = order.status;
      order.status = OrderStatus.CANCELLED;

      await this.orderRepository.save(order);

      // 이벤트 발행
      const cancelEvent = new OrderCancelledEvent(
        orderId,
        userId,
        reason,
        correlationId || uuidv4(),
      );

      const statusChangeEvent = new OrderStatusChangedEvent(
        orderId,
        previousStatus,
        OrderStatus.CANCELLED,
        correlationId || uuidv4(),
      );

      setImmediate(() => {
        this.eventBus.publishAll([cancelEvent, statusChangeEvent]);
      });

      this.logger.log(`Order cancelled successfully: ${orderId}`);
      
    } catch (error) {
      this.logger.error(`Failed to cancel order ${orderId}:`, error);
      throw error;
    }
  }
}

@CommandHandler(ConfirmOrderCommand)
export class ConfirmOrderHandler implements ICommandHandler<ConfirmOrderCommand> {
  private readonly logger = new Logger(ConfirmOrderHandler.name);

  constructor(
    @InjectRepository(Order)
    private readonly orderRepository: Repository<Order>,
    private readonly eventBus: EventBus,
  ) {}

  async execute(command: ConfirmOrderCommand): Promise<void> {
    const { orderId, paymentId, correlationId } = command;

    try {
      const order = await this.orderRepository.findOne({
        where: { id: orderId },
      });

      if (!order) {
        throw new NotFoundException('Order not found');
      }

      if (order.status !== OrderStatus.PENDING) {
        this.logger.warn(`Order cannot be confirmed, current status: ${order.status}`);
        return;
      }

      const previousStatus = order.status;
      order.status = OrderStatus.PAID;
      order.paymentId = paymentId;

      await this.orderRepository.save(order);

      // 이벤트 발행
      const confirmEvent = new OrderConfirmedEvent(
        orderId,
        paymentId,
        order.totalAmount,
        correlationId || uuidv4(),
      );

      const statusChangeEvent = new OrderStatusChangedEvent(
        orderId,
        previousStatus,
        OrderStatus.PAID,
        correlationId || uuidv4(),
      );

      setImmediate(() => {
        this.eventBus.publishAll([confirmEvent, statusChangeEvent]);
      });

      this.logger.log(`Order confirmed successfully: ${orderId}`);
      
    } catch (error) {
      this.logger.error(`Failed to confirm order ${orderId}:`, error);
      throw error;
    }
  }
}