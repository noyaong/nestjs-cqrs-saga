import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, QueryRunner, DataSource } from 'typeorm';
import { CommandBus } from '@nestjs/cqrs';
import { SagaInstance, SagaStatus } from './entities/saga-instance.entity';
import { KafkaService } from '../kafka/kafka.service';

export interface SagaStep {
  name: string;
  execute: () => Promise<void>;
  compensate: () => Promise<void>;
}

@Injectable()
export class SagaManager {
  private readonly logger = new Logger(SagaManager.name);

  constructor(
    @InjectRepository(SagaInstance)
    private readonly sagaRepository: Repository<SagaInstance>,
    private readonly commandBus: CommandBus,
    private readonly kafkaService: KafkaService,
    private readonly dataSource: DataSource,
  ) {}

  async startSaga(
    sagaType: string,
    correlationId: string,
    data: Record<string, any>,
    steps: SagaStep[],
  ): Promise<SagaInstance> {
    this.logger.log(`Starting saga: ${sagaType} with correlation ID: ${correlationId}`);

    try {
      // 기존 Saga 확인 (중복 방지)
      const existingSaga = await this.sagaRepository.findOne({
        where: { correlationId, sagaType },
      });

      if (existingSaga) {
        this.logger.warn(`Saga already exists for correlation ID: ${correlationId}`);
        return existingSaga;
      }

      // Saga 인스턴스 생성 (단순한 저장)
      const saga = this.sagaRepository.create({
        sagaType,
        correlationId,
        status: SagaStatus.STARTED,
        data,
        completedSteps: [],
        compensationSteps: [],
        currentStep: steps[0]?.name || 'initial',
      });

      const savedSaga = await this.sagaRepository.save(saga);

      // Saga 시작 이벤트 발행
      setImmediate(async () => {
        await this.kafkaService.publish('saga-events', {
          type: 'SagaStarted',
          sagaId: savedSaga.id,
          sagaType,
          correlationId,
          data,
          timestamp: new Date().toISOString(),
        });
      });

      return savedSaga;

    } catch (error) {
      this.logger.error(`Failed to start saga: ${sagaType}`, error);
      throw error;
    }
  }

  async executeSagaStep(
    sagaId: string,
    stepName: string,
    executeStep: () => Promise<void>,
  ): Promise<void> {
    try {
      const saga = await this.sagaRepository.findOne({
        where: { id: sagaId },
      });

      if (!saga) {
        throw new Error(`Saga not found: ${sagaId}`);
      }

      // 중복 실행 방지
      if (saga.completedSteps.includes(stepName)) {
        this.logger.warn(`Step ${stepName} already completed for saga: ${sagaId}`);
        return;
      }

      this.logger.log(`Executing saga step: ${stepName} for saga: ${sagaId}`);
      
      // 실행 상태 업데이트
      saga.currentStep = stepName;
      await this.sagaRepository.save(saga);

      // 단계 실행
      await executeStep();
      
      // 성공 시 완료된 단계에 추가
      saga.completedSteps.push(stepName);
      await this.sagaRepository.save(saga);

      setImmediate(async () => {
        await this.kafkaService.publish('saga-events', {
          type: 'SagaStepCompleted',
          sagaId,
          stepName,
          completedSteps: saga.completedSteps,
          timestamp: new Date().toISOString(),
        });
      });

      this.logger.log(`Saga step completed: ${stepName} for saga: ${sagaId}`);

    } catch (error) {
      this.logger.error(`Saga step failed: ${stepName} for saga: ${sagaId}`, error);
      
      const saga = await this.sagaRepository.findOne({
        where: { id: sagaId },
      });
      
      if (saga) {
        await this.handleSagaFailure(saga, stepName, error.message);
      }
    }
  }

  async completeSaga(sagaId: string): Promise<void> {
    try {
      const saga = await this.sagaRepository.findOne({
        where: { id: sagaId },
      });

      if (!saga) {
        throw new Error(`Saga not found: ${sagaId}`);
      }

      if (saga.status === SagaStatus.COMPLETED) {
        this.logger.warn(`Saga already completed: ${sagaId}`);
        return;
      }

      saga.status = SagaStatus.COMPLETED;
      saga.currentStep = 'completed';
      await this.sagaRepository.save(saga);

      setImmediate(async () => {
        await this.kafkaService.publish('saga-events', {
          type: 'SagaCompleted',
          sagaId,
          correlationId: saga.correlationId,
          completedSteps: saga.completedSteps,
          timestamp: new Date().toISOString(),
        });
      });

      this.logger.log(`Saga completed: ${sagaId}`);

    } catch (error) {
      this.logger.error(`Failed to complete saga: ${sagaId}`, error);
      throw error;
    }
  }

  async handleSagaFailure(
    saga: SagaInstance,
    failedStep: string,
    errorMessage: string,
  ): Promise<void> {
    const queryRunner = this.dataSource.createQueryRunner();
    await queryRunner.connect();
    await queryRunner.startTransaction();

    try {
      // 최신 상태로 다시 로드
      const freshSaga = await queryRunner.manager.findOne(SagaInstance, {
        where: { id: saga.id },
        lock: { mode: 'pessimistic_write' },
      });

      if (!freshSaga) {
        throw new Error(`Saga not found: ${saga.id}`);
      }

      freshSaga.status = SagaStatus.COMPENSATING;
      freshSaga.currentStep = failedStep;
      freshSaga.errorMessage = errorMessage;
      await queryRunner.manager.save(freshSaga);

      await queryRunner.commitTransaction();

      await this.kafkaService.publish('saga-events', {
        type: 'SagaFailed',
        sagaId: freshSaga.id,
        correlationId: freshSaga.correlationId,
        failedStep,
        errorMessage,
        timestamp: new Date().toISOString(),
      });

      // 보상 트랜잭션 시작
      await this.startCompensation(freshSaga);

    } catch (error) {
      await queryRunner.rollbackTransaction();
      throw error;
    } finally {
      await queryRunner.release();
    }
  }

  private async startCompensation(saga: SagaInstance): Promise<void> {
    this.logger.log(`Starting compensation for saga: ${saga.id}`);
    
    const queryRunner = this.dataSource.createQueryRunner();
    await queryRunner.connect();
    await queryRunner.startTransaction();

    try {
      // 완료된 단계들을 역순으로 보상
      const stepsToCompensate = [...saga.completedSteps].reverse();
      
      for (const step of stepsToCompensate) {
        await this.compensateStep(saga, step);
      }

      const freshSaga = await queryRunner.manager.findOne(SagaInstance, {
        where: { id: saga.id },
        lock: { mode: 'pessimistic_write' },
      });

      if (freshSaga) {
        freshSaga.status = SagaStatus.COMPENSATED;
        await queryRunner.manager.save(freshSaga);
      }

      await queryRunner.commitTransaction();

      await this.kafkaService.publish('saga-events', {
        type: 'SagaCompensated',
        sagaId: saga.id,
        correlationId: saga.correlationId,
        compensationSteps: saga.compensationSteps,
        timestamp: new Date().toISOString(),
      });

      this.logger.log(`Saga compensation completed: ${saga.id}`);

    } catch (compensationError) {
      await queryRunner.rollbackTransaction();
      
      // 보상 실패 시 최종 실패 상태로 설정
      await this.markSagaAsFinalFailure(saga, compensationError.message);
    } finally {
      await queryRunner.release();
    }
  }

  private async markSagaAsFinalFailure(saga: SagaInstance, errorMessage: string): Promise<void> {
    const queryRunner = this.dataSource.createQueryRunner();
    await queryRunner.connect();
    await queryRunner.startTransaction();

    try {
      const freshSaga = await queryRunner.manager.findOne(SagaInstance, {
        where: { id: saga.id },
        lock: { mode: 'pessimistic_write' },
      });

      if (freshSaga) {
        freshSaga.status = SagaStatus.FAILED;
        freshSaga.errorMessage = `Compensation failed: ${errorMessage}`;
        await queryRunner.manager.save(freshSaga);
      }

      await queryRunner.commitTransaction();

      await this.kafkaService.publish('saga-events', {
        type: 'SagaCompensationFailed',
        sagaId: saga.id,
        correlationId: saga.correlationId,
        error: freshSaga?.errorMessage,
        requiresManualIntervention: true,
        timestamp: new Date().toISOString(),
      });

    } catch (error) {
      await queryRunner.rollbackTransaction();
      this.logger.error(`Failed to mark saga as final failure: ${saga.id}`, error);
    } finally {
      await queryRunner.release();
    }
  }

  private async compensateStep(saga: SagaInstance, stepName: string): Promise<void> {
    this.logger.log(`Compensating step: ${stepName} for saga: ${saga.id}`);
    
    // 실제 보상 로직은 각 단계별로 구현
    saga.compensationSteps.push(`compensate_${stepName}`);

    await this.kafkaService.publish('saga-events', {
      type: 'SagaStepCompensated',
      sagaId: saga.id,
      stepName: `compensate_${stepName}`,
      timestamp: new Date().toISOString(),
    });
  }

  async findSagaById(sagaId: string): Promise<SagaInstance | null> {
    return this.sagaRepository.findOne({ where: { id: sagaId } });
  }

  async findSagaByCorrelationId(correlationId: string, sagaType?: string): Promise<SagaInstance | null> {
    const where: any = { correlationId };
    if (sagaType) {
      where.sagaType = sagaType;
    }
    return this.sagaRepository.findOne({ where });
  }

  async getAllSagas(page: number = 1, limit: number = 10): Promise<{ sagas: SagaInstance[]; total: number }> {
    const [sagas, total] = await this.sagaRepository.findAndCount({
      order: { createdAt: 'DESC' },
      skip: (page - 1) * limit,
      take: limit,
    });

    return { sagas, total };
  }

  async getSagasByStatus(status: SagaStatus): Promise<SagaInstance[]> {
    return this.sagaRepository.find({
      where: { status },
      order: { createdAt: 'DESC' },
    });
  }
}