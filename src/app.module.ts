import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { CqrsModule } from '@nestjs/cqrs';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { DatabaseModule } from './database/database.module';
import { AuthModule } from './auth/auth.module';
import { OrderModule } from './order/order.module';
import { PaymentModule } from './payment/payment.module';
import { SagaModule } from './saga/saga.module';
import { KafkaModule } from './kafka/kafka.module';
import { TracingModule } from './tracing/tracing.module';
import { databaseConfig } from './config/database.config';
import { jwtConfig } from './config/jwt.config';
import { kafkaConfig } from './config/kafka.config';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      load: [databaseConfig, jwtConfig, kafkaConfig],
    }),
    CqrsModule,
    DatabaseModule,
    KafkaModule,
    AuthModule,
    OrderModule,
    PaymentModule,
    SagaModule,
    TracingModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}