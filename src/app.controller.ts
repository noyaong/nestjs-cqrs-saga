import { Controller, Get, UseGuards, Request } from '@nestjs/common';
import { AppService } from './app.service';
import { InjectConnection } from '@nestjs/typeorm';
import { Connection } from 'typeorm';
import { JwtAuthGuard } from './auth/guards/jwt-auth.guard';
import { ApiBearerAuth, ApiTags, ApiOperation } from '@nestjs/swagger';
import { KafkaService } from './kafka/kafka.service';

@ApiTags('App')
@Controller()
export class AppController {
  constructor(
    private readonly appService: AppService,
    @InjectConnection() private readonly connection: Connection,
    private readonly kafkaService: KafkaService,
  ) {}

  @Get()
  @ApiOperation({ summary: '홈페이지' })
  getHello(): string {
    return this.appService.getHello();
  }
  @Get('db-pool')
  @ApiOperation({ summary: '데이터베이스 커넥션 풀 상태' })
  async getDatabasePoolStatus() {
    try {
      // 활성 커넥션 수 확인
      const result = await this.connection.query(
        `SELECT count(*) as active_connections 
         FROM pg_stat_activity 
         WHERE state = 'active' AND datname = current_database()`
      );
      
      return {
        status: 'success',
        activeConnections: parseInt(result[0].active_connections),
        maxConnections: 20, // 설정한 최대값
        isHealthy: parseInt(result[0].active_connections) < 15,
      };
    } catch (error) {
      return {
        status: 'error',
        message: 'Failed to check database pool',
        error: error.message,
      };
    }
  }
  @Get('kafka-test')
  @ApiOperation({ summary: 'Kafka 테스트 메시지 발송' })
  async testKafka() {
    try {
      await this.kafkaService.publish('test-topic', {
        message: 'Hello Kafka!',
        timestamp: new Date().toISOString(),
      });
      
      return {
        status: 'success',
        message: 'Kafka test message sent',
      };
    } catch (error) {
      return {
        status: 'error',
        message: 'Failed to send Kafka message',
        error: error.message,
      };
    }
  }

  @Get('health')
  @ApiOperation({ summary: '헬스 체크 및 데이터베이스 연결 상태' })
  async getHealth() {
    const dbConnected = this.connection.isConnected;
    
    return {
      status: 'ok',
      timestamp: new Date().toISOString(),
      environment: process.env.NODE_ENV,
      database: {
        connected: dbConnected,
        name: this.connection.options.database,
      },
    };
  }

  @Get('db-test')
  async testDatabase() {
    try {
      const result = await this.connection.query('SELECT NOW() as current_time');
      return {
        status: 'success',
        message: 'Database connection successful',
        data: result[0],
      };
    } catch (error) {
      return {
        status: 'error',
        message: 'Database connection failed',
        error: error.message,
      };
    }
  }

  @Get('protected')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'JWT 인증이 필요한 테스트 엔드포인트' })
  getProtected(@Request() req) {
    return {
      message: '인증된 사용자만 볼 수 있는 데이터입니다! 🔒',
      user: {
        id: req.user.id,
        email: req.user.email,
        role: req.user.role,
      },
      timestamp: new Date().toISOString(),
    };
  }
}