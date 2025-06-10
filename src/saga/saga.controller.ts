import {
  Controller,
  Get,
  Param,
  Query,
  UseGuards,
  ParseUUIDPipe,
  ParseIntPipe,
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
import { SagaManager } from './saga-manager.service';
import { OrderProcessingSaga } from './order-processing.saga';
import { SagaStatus } from './entities/saga-instance.entity';

@ApiTags('Saga Management')
@Controller('sagas')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class SagaController {
  constructor(
    private readonly sagaManager: SagaManager,
    private readonly orderProcessingSaga: OrderProcessingSaga,
  ) {}

  @Get()
  @ApiOperation({ summary: '모든 Saga 인스턴스 조회' })
  @ApiQuery({ name: 'page', required: false, example: 1 })
  @ApiQuery({ name: 'limit', required: false, example: 10 })
  @ApiResponse({
    status: 200,
    description: 'Saga 목록 조회 성공',
  })
  async getAllSagas(
    @Query('page', new ParseIntPipe({ optional: true })) page: number = 1,
    @Query('limit', new ParseIntPipe({ optional: true })) limit: number = 10,
  ) {
    const result = await this.sagaManager.getAllSagas(page, limit);
    
    return {
      sagas: result.sagas.map(saga => ({
        id: saga.id,
        sagaType: saga.sagaType,
        correlationId: saga.correlationId,
        status: saga.status,
        currentStep: saga.currentStep,
        completedSteps: saga.completedSteps,
        compensationSteps: saga.compensationSteps,
        data: saga.data,
        errorMessage: saga.errorMessage,
        createdAt: saga.createdAt,
        updatedAt: saga.updatedAt,
      })),
      total: result.total,
      page,
      limit,
      totalPages: Math.ceil(result.total / limit),
    };
  }

  @Get('status/:status')
  @ApiOperation({ summary: '상태별 Saga 조회' })
  @ApiParam({ 
    name: 'status', 
    enum: SagaStatus,
    description: 'Saga 상태'
  })
  @ApiResponse({
    status: 200,
    description: '상태별 Saga 조회 성공',
  })
  async getSagasByStatus(@Param('status') status: SagaStatus) {
    const sagas = await this.sagaManager.getSagasByStatus(status);
    
    return {
      status,
      count: sagas.length,
      sagas: sagas.map(saga => ({
        id: saga.id,
        sagaType: saga.sagaType,
        correlationId: saga.correlationId,
        currentStep: saga.currentStep,
        data: saga.data,
        errorMessage: saga.errorMessage,
        createdAt: saga.createdAt,
      })),
    };
  }

  @Get('correlation/:correlationId')
  @ApiOperation({ summary: 'Correlation ID로 Saga 조회' })
  @ApiParam({ name: 'correlationId', description: 'Correlation ID' })
  @ApiResponse({
    status: 200,
    description: 'Saga 조회 성공',
  })
  async getSagaByCorrelationId(@Param('correlationId') correlationId: string) {
    const saga = await this.sagaManager.findSagaByCorrelationId(correlationId);
    
    if (!saga) {
      return {
        message: 'Saga not found',
        correlationId,
      };
    }

    return {
      id: saga.id,
      sagaType: saga.sagaType,
      correlationId: saga.correlationId,
      status: saga.status,
      currentStep: saga.currentStep,
      completedSteps: saga.completedSteps,
      compensationSteps: saga.compensationSteps,
      data: saga.data,
      errorMessage: saga.errorMessage,
      createdAt: saga.createdAt,
      updatedAt: saga.updatedAt,
    };
  }

  @Get(':id')
  @ApiOperation({ summary: 'ID로 Saga 상세 조회' })
  @ApiParam({ name: 'id', description: 'Saga ID' })
  @ApiResponse({
    status: 200,
    description: 'Saga 상세 조회 성공',
  })
  async getSagaById(@Param('id', ParseUUIDPipe) id: string) {
    const saga = await this.sagaManager.findSagaById(id);
    
    if (!saga) {
      return {
        message: 'Saga not found',
        id,
      };
    }

    return {
      id: saga.id,
      sagaType: saga.sagaType,
      correlationId: saga.correlationId,
      status: saga.status,
      currentStep: saga.currentStep,
      completedSteps: saga.completedSteps,
      compensationSteps: saga.compensationSteps,
      data: saga.data,
      errorMessage: saga.errorMessage,
      createdAt: saga.createdAt,
      updatedAt: saga.updatedAt,
    };
  }

  @Get('orders/processing')
  @ApiOperation({ summary: '주문 처리 Saga 목록 조회' })
  @ApiResponse({
    status: 200,
    description: '주문 처리 Saga 목록 조회 성공',
  })
  async getOrderProcessingSagas() {
    const sagas = await this.orderProcessingSaga.getAllOrderSagas();
    
    return {
      sagaType: 'OrderProcessingSaga',
      count: sagas.length,
      sagas: sagas.map(saga => ({
        id: saga.id,
        correlationId: saga.correlationId,
        status: saga.status,
        currentStep: saga.currentStep,
        orderId: saga.data.orderId,
        userId: saga.data.userId,
        totalAmount: saga.data.totalAmount,
        completedSteps: saga.completedSteps,
        compensationSteps: saga.compensationSteps,
        errorMessage: saga.errorMessage,
        createdAt: saga.createdAt,
        updatedAt: saga.updatedAt,
      })),
    };
  }
}