import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
} from 'typeorm';

export enum SagaStatus {
  STARTED = 'started',
  COMPLETED = 'completed',
  FAILED = 'failed',
  COMPENSATING = 'compensating',
  COMPENSATED = 'compensated',
}

@Entity('saga_instances')
export class SagaInstance {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  sagaType: string; // 'OrderProcessingSaga', 'PaymentProcessingSaga' etc.

  @Column()
  correlationId: string; // 비즈니스 프로세스 추적 ID

  @Column({
    type: 'enum',
    enum: SagaStatus,
    default: SagaStatus.STARTED,
  })
  status: SagaStatus;

  @Column('jsonb')
  data: Record<string, any>; // Saga 실행에 필요한 데이터

  @Column('jsonb', { default: [] })
  completedSteps: string[]; // 완료된 단계들

  @Column('jsonb', { default: [] })
  compensationSteps: string[]; // 보상 단계들

  @Column({ nullable: true })
  currentStep: string;

  @Column({ nullable: true })
  errorMessage: string;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}