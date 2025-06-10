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

    try {
      // 총 금액 계산
      const totalAmount = items.reduce((sum, item) => sum + (item.price * item.quantity), 0);

      // 단순한 트랜잭션으로 주문 생성 (queryRunner 사용하지 않음)
      const order = this.orderRepository.create({
        userId,
        totalAmount,
        items,
        shippingAddress,
        status: OrderStatus.PENDING,
      });

      const savedOrder = await this.orderRepository.save(order);
      
      this.logger.log(`Order created successfully: ${savedOrder.id}`);

      // 이벤트 발행 (트랜잭션 외부에서)
      const event = new OrderCreatedEvent(
        savedOrder.id,
        savedOrder.userId,
        savedOrder.totalAmount,
        savedOrder.items,
        savedOrder.shippingAddress,
        correlationId || uuidv4(),
      );

      // 비동기로 이벤트 발행 (연결 블로킹 방지)
      setImmediate(() => {
        this.eventBus.publish(event);
      });

      return savedOrder;
      
    } catch (error) {
      this.logger.error(`Failed to create order for user ${userId}:`, error);
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