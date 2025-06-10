import {
  Controller,
  Post,
  Get,
  UseGuards,
  Query,
  ParseIntPipe,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiResponse,
  ApiBearerAuth,
  ApiQuery,
} from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { SagaManager } from './saga-manager.service';
import { OrderProcessingSaga } from './order-processing.saga';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { SagaInstance, SagaStatus } from './entities/saga-instance.entity';
import { Order, OrderStatus } from '../order/entities/order.entity';
import { Payment, PaymentStatus } from '../payment/entities/payment.entity';
import { CommandBus } from '@nestjs/cqrs';
import { CancelOrderCommand } from '../order/commands/order.commands';

@ApiTags('Saga Maintenance')
@Controller('saga/maintenance')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class SagaMaintenanceController {
  constructor(
    private readonly sagaManager: SagaManager,
    private readonly orderProcessingSaga: OrderProcessingSaga,
    @InjectRepository(SagaInstance)
    private readonly sagaRepository: Repository<SagaInstance>,
    @InjectRepository(Order)
    private readonly orderRepository: Repository<Order>,
    @InjectRepository(Payment)
    private readonly paymentRepository: Repository<Payment>,
    private readonly commandBus: CommandBus,
  ) {}

  @Get('pending-orders')
  @ApiOperation({ summary: 'Pending 상태 주문들과 관련 Saga 조회' })
  @ApiResponse({
    status: 200,
    description: 'Pending 주문 및 Saga 상태 조회 성공',
  })
  async getPendingOrders() {
    const pendingOrders = await this.orderRepository.find({
      where: { status: OrderStatus.PENDING },
      order: { createdAt: 'DESC' },
    });

    const result = [];
    
    for (const order of pendingOrders) {
      // 관련 Saga 찾기
      const saga = await this.sagaRepository.findOne({
        where: { 
          sagaType: 'OrderProcessingSaga',
          data: { orderId: order.id } as any 
        },
      });

      // 관련 Payment 찾기
      const payment = await this.paymentRepository.findOne({
        where: { orderId: order.id },
      });

      result.push({
        order: {
          id: order.id,
          status: order.status,
          totalAmount: order.totalAmount,
          createdAt: order.createdAt,
        },
        saga: saga ? {
          id: saga.id,
          status: saga.status,
          currentStep: saga.currentStep,
          completedSteps: saga.completedSteps,
          errorMessage: saga.errorMessage,
        } : null,
        payment: payment ? {
          id: payment.id,
          status: payment.status,
          failureReason: payment.failureReason,
        } : null,
      });
    }

    return {
      count: result.length,
      orders: result,
    };
  }

  @Post('cleanup-pending')
  @ApiOperation({ summary: 'Pending 상태 주문들 정리 (보상 트랜잭션 실행)' })
  @ApiResponse({
    status: 200,
    description: 'Pending 주문 정리 완료',
  })
  async cleanupPendingOrders() {
    const pendingOrders = await this.orderRepository.find({
      where: { status: OrderStatus.PENDING },
    });

    const results = [];

    for (const order of pendingOrders) {
      try {
        // 결제 상태 확인
        const payment = await this.paymentRepository.findOne({
          where: { orderId: order.id },
        });

        if (payment && payment.status === PaymentStatus.FAILED) {
          // 결제 실패한 경우 주문 취소
          const cancelCommand = new CancelOrderCommand(
            order.id,
            order.userId,
            `Cleanup: Payment failed - ${payment.failureReason}`,
          );

          await this.commandBus.execute(cancelCommand);

          // Saga 상태도 보상 완료로 업데이트
          const saga = await this.sagaRepository.findOne({
            where: { 
              sagaType: 'OrderProcessingSaga',
              data: { orderId: order.id } as any 
            },
          });

          if (saga) {
            saga.status = SagaStatus.COMPENSATED;
            saga.compensationSteps.push('order_cancelled_cleanup');
            await this.sagaRepository.save(saga);
          }

          results.push({
            orderId: order.id,
            action: 'cancelled',
            reason: 'Payment failed',
          });

        } else if (!payment) {
          // 결제 기록이 없는 경우도 취소
          const cancelCommand = new CancelOrderCommand(
            order.id,
            order.userId,
            'Cleanup: No payment record found',
          );

          await this.commandBus.execute(cancelCommand);

          results.push({
            orderId: order.id,
            action: 'cancelled',
            reason: 'No payment record',
          });
        }

      } catch (error) {
        results.push({
          orderId: order.id,
          action: 'error',
          reason: error.message,
        });
      }
    }

    return {
      message: 'Pending orders cleanup completed',
      processed: results.length,
      results,
    };
  }

  @Get('saga-health')
  @ApiOperation({ summary: 'Saga 시스템 전체 건강 상태 확인' })
  @ApiResponse({
    status: 200,
    description: 'Saga 건강 상태 조회 성공',
  })
  async getSagaHealth() {
    const [
      totalSagas,
      startedSagas,
      completedSagas,
      failedSagas,
      compensatedSagas,
    ] = await Promise.all([
      this.sagaRepository.count(),
      this.sagaRepository.count({ where: { status: SagaStatus.STARTED } }),
      this.sagaRepository.count({ where: { status: SagaStatus.COMPLETED } }),
      this.sagaRepository.count({ where: { status: SagaStatus.FAILED } }),
      this.sagaRepository.count({ where: { status: SagaStatus.COMPENSATED } }),
    ]);

    const [
      totalOrders,
      pendingOrders,
      paidOrders,
      cancelledOrders,
    ] = await Promise.all([
      this.orderRepository.count(),
      this.orderRepository.count({ where: { status: OrderStatus.PENDING } }),
      this.orderRepository.count({ where: { status: OrderStatus.PAID } }),
      this.orderRepository.count({ where: { status: OrderStatus.CANCELLED } }),
    ]);

    return {
      sagas: {
        total: totalSagas,
        started: startedSagas,
        completed: completedSagas,
        failed: failedSagas,
        compensated: compensatedSagas,
      },
      orders: {
        total: totalOrders,
        pending: pendingOrders,
        paid: paidOrders,
        cancelled: cancelledOrders,
      },
      issues: {
        orphanedPendingOrders: pendingOrders > startedSagas,
        stuckSagas: startedSagas,
      },
    };
  }
}