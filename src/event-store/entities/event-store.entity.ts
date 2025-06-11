import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  Index,
} from 'typeorm';

@Entity('event_store')
@Index(['aggregateId', 'version'])
export class EventStore {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  @Index()
  aggregateId: string;

  @Column()
  aggregateType: string;

  @Column()
  eventType: string;

  @Column('jsonb')
  eventData: Record<string, any>;

  @Column('jsonb', { nullable: true })
  metadata: Record<string, any>;

  @Column({ type: 'int', default: 1 })
  version: number;

  @CreateDateColumn()
  occurredAt: Date;

  @Column({ type: 'text', nullable: true })
  causationId: string; // 이 이벤트를 발생시킨 커맨드/이벤트 ID

  @Column({ type: 'text', nullable: true })
  correlationId: string; // 전체 비즈니스 프로세스 추적 ID
}