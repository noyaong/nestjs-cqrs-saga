import {
  Controller,
  Get,
  Param,
  UseGuards,
  Query,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiResponse,
  ApiBearerAuth,
  ApiParam,
  ApiQuery,
} from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { SagaInstance, SagaStatus } from '../saga/entities/saga-instance.entity';
import { Order } from '../order/entities/order.entity';
import { Payment } from '../payment/entities/payment.entity';
import { EventStore } from '../event-store/entities/event-store.entity';

@ApiTags('Tracing')
@Controller('trace')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class TracingController {
  constructor(
    @InjectRepository(SagaInstance)
    private readonly sagaRepository: Repository<SagaInstance>,
    @InjectRepository(Order)
    private readonly orderRepository: Repository<Order>,
    @InjectRepository(Payment)
    private readonly paymentRepository: Repository<Payment>,
    @InjectRepository(EventStore)
    private readonly eventStoreRepository: Repository<EventStore>,
  ) {}

  @Get('correlation/:correlationId')
  @ApiOperation({ summary: 'Correlation ID로 전체 플로우 추적' })
  @ApiParam({ name: 'correlationId', description: 'Correlation ID' })
  @ApiResponse({
    status: 200,
    description: '전체 플로우 추적 성공',
  })
  async traceByCorrelationId(@Param('correlationId') correlationId: string) {
    // 1. Saga 조회
    const saga = await this.sagaRepository.findOne({
      where: { correlationId },
    });

    if (!saga) {
      return {
        correlationId,
        found: false,
        message: 'No saga found with this correlation ID',
      };
    }

    // 2. Order 조회
    const orderId = saga.data.orderId;
    const order = await this.orderRepository.findOne({
      where: { id: orderId },
    });

    // 3. Payment 조회
    const payment = await this.paymentRepository.findOne({
      where: { orderId },
    });

    // 4. 관련 Events 조회
    const events = await this.eventStoreRepository.find({
      where: { correlationId },
      order: { occurredAt: 'ASC' },
    });

    // 5. 타임라인 구성
    const timeline = events.map(event => ({
      timestamp: event.occurredAt,
      eventType: event.eventType,
      aggregateType: event.aggregateType,
      aggregateId: event.aggregateId,
      data: event.eventData,
    }));

    return {
      correlationId,
      found: true,
      saga: {
        id: saga.id,
        type: saga.sagaType,
        status: saga.status,
        currentStep: saga.currentStep,
        completedSteps: saga.completedSteps,
        compensationSteps: saga.compensationSteps,
        errorMessage: saga.errorMessage,
        createdAt: saga.createdAt,
        updatedAt: saga.updatedAt,
      },
      order: order ? {
        id: order.id,
        status: order.status,
        totalAmount: order.totalAmount,
        items: order.items,
        paymentId: order.paymentId,
        createdAt: order.createdAt,
        updatedAt: order.updatedAt,
      } : null,
      payment: payment ? {
        id: payment.id,
        status: payment.status,
        amount: payment.amount,
        method: payment.method,
        externalTransactionId: payment.externalTransactionId,
        failureReason: payment.failureReason,
        createdAt: payment.createdAt,
        updatedAt: payment.updatedAt,
      } : null,
      timeline,
      summary: {
        totalEvents: events.length,
        sagaStatus: saga.status,
        orderStatus: order?.status || 'not_found',
        paymentStatus: payment?.status || 'not_found',
        duration: saga.updatedAt.getTime() - saga.createdAt.getTime(),
        isSuccessful: saga.status === 'completed',
      },
    };
  }

  @Get('order/:orderId')
  @ApiOperation({ summary: 'Order ID로 관련 플로우 추적' })
  @ApiParam({ name: 'orderId', description: 'Order ID' })
  @ApiResponse({
    status: 200,
    description: '주문 관련 플로우 추적 성공',
  })
  async traceByOrderId(@Param('orderId') orderId: string) {
    // Order 조회
    const order = await this.orderRepository.findOne({
      where: { id: orderId },
    });

    if (!order) {
      return {
        orderId,
        found: false,
        message: 'Order not found',
      };
    }

    // 관련 Saga 찾기 (data에서 orderId 검색)
    const sagas = await this.sagaRepository
      .createQueryBuilder('saga')
      .where("saga.data->>'orderId' = :orderId", { orderId })
      .getMany();

    // Payment 조회
    const payment = await this.paymentRepository.findOne({
      where: { orderId },
    });

    // 모든 관련 Events 조회
    const events = await this.eventStoreRepository
      .createQueryBuilder('event')
      .where("event.eventData->>'orderId' = :orderId", { orderId })
      .orWhere("event.aggregateId = :orderId", { orderId })
      .orderBy('event.occurredAt', 'ASC')
      .getMany();

    return {
      orderId,
      found: true,
      order: {
        id: order.id,
        status: order.status,
        totalAmount: order.totalAmount,
        items: order.items,
        userId: order.userId,
        paymentId: order.paymentId,
        createdAt: order.createdAt,
        updatedAt: order.updatedAt,
      },
      sagas: sagas.map(saga => ({
        id: saga.id,
        correlationId: saga.correlationId,
        status: saga.status,
        currentStep: saga.currentStep,
        completedSteps: saga.completedSteps,
        compensationSteps: saga.compensationSteps,
        errorMessage: saga.errorMessage,
      })),
      payment: payment ? {
        id: payment.id,
        status: payment.status,
        amount: payment.amount,
        method: payment.method,
        externalTransactionId: payment.externalTransactionId,
        failureReason: payment.failureReason,
        createdAt: payment.createdAt,
        updatedAt: payment.updatedAt,
      } : null,
      events: events.map(event => ({
        timestamp: event.occurredAt,
        eventType: event.eventType,
        aggregateType: event.aggregateType,
        aggregateId: event.aggregateId,
        data: event.eventData,
        correlationId: event.correlationId,
      })),
      summary: {
        totalEvents: events.length,
        totalSagas: sagas.length,
        hasPayment: !!payment,
        finalStatus: {
          order: order.status,
          payment: payment?.status || 'none',
          saga: sagas[0]?.status || 'none',
        },
      },
    };
  }

  @Get('events')
  @ApiOperation({ summary: '모든 이벤트 스트림 조회 (최근 순)' })
  @ApiQuery({ name: 'limit', required: false, example: 50 })
  @ApiQuery({ name: 'eventType', required: false, description: '이벤트 타입 필터' })
  @ApiResponse({
    status: 200,
    description: '이벤트 스트림 조회 성공',
  })
  async getAllEvents(
    @Query('limit') limit: number = 50,
    @Query('eventType') eventType?: string,
  ) {
    const queryBuilder = this.eventStoreRepository
      .createQueryBuilder('event')
      .orderBy('event.occurredAt', 'DESC')
      .limit(Math.min(limit, 100)); // 최대 100개로 제한

    if (eventType) {
      queryBuilder.where('event.eventType = :eventType', { eventType });
    }

    const events = await queryBuilder.getMany();

    // 이벤트 타입별 통계
    const eventTypes = await this.eventStoreRepository
      .createQueryBuilder('event')
      .select('event.eventType', 'eventType')
      .addSelect('COUNT(*)', 'count')
      .groupBy('event.eventType')
      .getRawMany();

    return {
      events: events.map(event => ({
        id: event.id,
        timestamp: event.occurredAt,
        eventType: event.eventType,
        aggregateType: event.aggregateType,
        aggregateId: event.aggregateId,
        correlationId: event.correlationId,
        data: event.eventData,
        metadata: event.metadata,
      })),
      statistics: {
        totalReturned: events.length,
        eventTypeDistribution: eventTypes.reduce((acc, item) => {
          acc[item.eventType] = parseInt(item.count);
          return acc;
        }, {}),
      },
    };
  }

  @Get('active-flows')
  @ApiOperation({ summary: '현재 진행 중인 플로우들' })
  @ApiResponse({
    status: 200,
    description: '진행 중인 플로우 조회 성공',
  })
  async getActiveFlows() {
    // 진행 중인 Saga들
    const activeSagas = await this.sagaRepository.find({
      where: [
        { status: SagaStatus.STARTED },
        { status: SagaStatus.COMPENSATING },
      ],
      order: { createdAt: 'DESC' },
    });

    const flows = [];

    for (const saga of activeSagas) {
      const orderId = saga.data.orderId;
      
      // 관련 Order와 Payment 조회
      const [order, payment] = await Promise.all([
        this.orderRepository.findOne({ where: { id: orderId } }),
        this.paymentRepository.findOne({ where: { orderId } }),
      ]);

      // 최근 이벤트 조회
      const recentEvents = await this.eventStoreRepository.find({
        where: { correlationId: saga.correlationId },
        order: { occurredAt: 'DESC' },
        take: 3,
      });

      flows.push({
        correlationId: saga.correlationId,
        saga: {
          id: saga.id,
          status: saga.status,
          currentStep: saga.currentStep,
          completedSteps: saga.completedSteps,
          errorMessage: saga.errorMessage,
          duration: Date.now() - saga.createdAt.getTime(),
        },
        order: order ? {
          id: order.id,
          status: order.status,
          totalAmount: order.totalAmount,
        } : null,
        payment: payment ? {
          id: payment.id,
          status: payment.status,
          failureReason: payment.failureReason,
        } : null,
        recentEvents: recentEvents.map(e => ({
          eventType: e.eventType,
          timestamp: e.occurredAt,
        })),
        isStuck: Date.now() - saga.updatedAt.getTime() > 60000, // 1분 이상 업데이트 없음
      });
    }

    return {
      totalActiveFlows: flows.length,
      stuckFlows: flows.filter(f => f.isStuck).length,
      flows,
    };
  }
}