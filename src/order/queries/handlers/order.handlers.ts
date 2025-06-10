import { IQueryHandler, QueryHandler } from '@nestjs/cqrs';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Order } from '../../entities/order.entity';
import { 
  GetOrderByIdQuery, 
  GetOrdersByUserIdQuery, 
  GetOrdersQuery 
} from '../order.queries';
import { NotFoundException, ForbiddenException } from '@nestjs/common';

@QueryHandler(GetOrderByIdQuery)
export class GetOrderByIdHandler implements IQueryHandler<GetOrderByIdQuery> {
  constructor(
    @InjectRepository(Order)
    private readonly orderRepository: Repository<Order>,
  ) {}

  async execute(query: GetOrderByIdQuery): Promise<Order> {
    const { orderId, userId } = query;

    const order = await this.orderRepository.findOne({
      where: { id: orderId },
      relations: ['user'],
    });

    if (!order) {
      throw new NotFoundException('Order not found');
    }

    // 권한 확인 (관리자가 아닌 경우 본인 주문만 조회 가능)
    if (userId && order.userId !== userId) {
      throw new ForbiddenException('Access denied');
    }

    return order;
  }
}

@QueryHandler(GetOrdersByUserIdQuery)
export class GetOrdersByUserIdHandler implements IQueryHandler<GetOrdersByUserIdQuery> {
  constructor(
    @InjectRepository(Order)
    private readonly orderRepository: Repository<Order>,
  ) {}

  async execute(query: GetOrdersByUserIdQuery): Promise<{ orders: Order[]; total: number }> {
    const { userId, page, limit, status } = query;

    const queryBuilder = this.orderRepository
      .createQueryBuilder('order')
      .where('order.userId = :userId', { userId });

    if (status) {
      queryBuilder.andWhere('order.status = :status', { status });
    }

    const [orders, total] = await queryBuilder
      .orderBy('order.createdAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit)
      .getManyAndCount();

    return { orders, total };
  }
}

@QueryHandler(GetOrdersQuery)
export class GetOrdersHandler implements IQueryHandler<GetOrdersQuery> {
  constructor(
    @InjectRepository(Order)
    private readonly orderRepository: Repository<Order>,
  ) {}

  async execute(query: GetOrdersQuery): Promise<{ orders: Order[]; total: number }> {
    const { page, limit, status, userId } = query;

    const queryBuilder = this.orderRepository
      .createQueryBuilder('order')
      .leftJoinAndSelect('order.user', 'user');

    if (status) {
      queryBuilder.andWhere('order.status = :status', { status });
    }

    if (userId) {
      queryBuilder.andWhere('order.userId = :userId', { userId });
    }

    const [orders, total] = await queryBuilder
      .orderBy('order.createdAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit)
      .getManyAndCount();

    return { orders, total };
  }
}