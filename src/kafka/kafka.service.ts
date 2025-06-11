import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Kafka, Producer, Consumer, EachMessagePayload } from 'kafkajs';
import { createHash } from 'crypto';

@Injectable()
export class KafkaService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(KafkaService.name);
  private kafka: Kafka;
  private producer: Producer;
  private consumers: Map<string, Consumer> = new Map();
  private messageHandlers: Map<string, (message: any) => Promise<void>> = new Map();

  constructor(private readonly configService: ConfigService) {
    this.kafka = new Kafka({
      clientId: this.configService.get<string>('kafka.clientId'),
      brokers: [this.configService.get<string>('kafka.broker')],
      retry: {
        initialRetryTime: 100,
        retries: 8,
      },
    });
  }

  async onModuleInit() {
    this.producer = this.kafka.producer();
    await this.producer.connect();
    this.logger.log('Kafka producer connected');
    
    // 필요한 토픽들 생성
    const topics = [
      this.configService.get<string>('kafka.topics.orderEvents'),
      this.configService.get<string>('kafka.topics.paymentEvents'),
      this.configService.get<string>('kafka.topics.sagaEvents'),
    ];
    
    await this.createTopics(topics);
  }

  async onModuleDestroy() {
    await this.producer.disconnect();
    
    for (const [groupId, consumer] of this.consumers) {
      await consumer.disconnect();
      this.logger.log(`Kafka consumer disconnected: ${groupId}`);
    }
  }

  /**
   * 상품 정보를 기반으로 토픽 이름 생성
   */
  private generateTopicForProduct(baseEventType: string, productInfo?: any): string {
    if (!productInfo || !productInfo.items || productInfo.items.length === 0) {
      return baseEventType; // 기본 토픽 사용
    }

    // 첫 번째 상품의 ID를 기반으로 토픽 생성
    const primaryProduct = productInfo.items[0];
    const productId = primaryProduct.productId || primaryProduct.productName || 'unknown';
    
    // 상품 ID를 해시하여 안전한 토픽 이름 생성
    const productHash = createHash('md5')
      .update(productId)
      .digest('hex')
      .substring(0, 8);
    
    return `${baseEventType}-product-${productHash}`;
  }

  /**
   * 이벤트 타입과 데이터를 기반으로 적절한 토픽 선택
   */
  private selectTopic(eventType: string, data: any): string {
    // Order 관련 이벤트는 상품별 토픽 사용
    if (eventType.includes('Order') || eventType.includes('order')) {
      return this.generateTopicForProduct('order-events', data);
    }
    
    // Payment 관련 이벤트는 상품별 토픽 사용
    if (eventType.includes('Payment') || eventType.includes('payment')) {
      return this.generateTopicForProduct('payment-events', data);
    }
    
    // Saga 이벤트는 correlationId 기반 토픽 사용
    if (eventType.includes('Saga') || eventType.includes('saga')) {
      if (data.correlationId) {
        const correlationHash = createHash('md5')
          .update(data.correlationId)
          .digest('hex')
          .substring(0, 8);
        return `saga-events-${correlationHash}`;
      }
      return 'saga-events';
    }
    
    // 기본 토픽들
    return eventType.toLowerCase().includes('saga') ? 'saga-events' : 'order-events';
  }

  async publish(topic: string, message: any): Promise<void> {
    try {
      // 동적 토픽 선택
      const selectedTopic = this.selectTopic(topic, message);
      
      this.logger.log(`📤 Publishing to topic: ${selectedTopic}`);
      this.logger.log(`📋 Message type: ${message.type || 'unknown'}`);
      
      await this.producer.send({
        topic: selectedTopic,
        messages: [
          {
            key: message.correlationId || message.sagaId || message.orderId || Date.now().toString(),
            value: JSON.stringify(message),
            timestamp: Date.now().toString(),
          },
        ],
      });

      this.logger.log(`✅ Message published to ${selectedTopic}`);
    } catch (error) {
      this.logger.error(`❌ Failed to publish message to ${topic}:`, error);
      throw error;
    }
  }

  async subscribe(
    topicPattern: string,
    groupId: string,
    handler: (message: any) => Promise<void>,
  ): Promise<void> {
    try {
      const consumer = this.kafka.consumer({ 
        groupId,
        maxWaitTimeInMs: 3000,
        sessionTimeout: 30000,
        heartbeatInterval: 3000,
      });

      // 패턴 기반 구독 (정규표현식 지원)
      const isPattern = topicPattern.includes('*') || topicPattern.includes('.');
      
      if (isPattern) {
        // 패턴 구독 (예: order-events-*, saga-events-*)
        await consumer.subscribe({ 
          topic: new RegExp(topicPattern.replace('*', '.*')),
          fromBeginning: false 
        });
        this.logger.log(`📡 Subscribed to pattern: ${topicPattern}`);
      } else {
        // 정확한 토픽 구독
        await consumer.subscribe({ 
          topic: topicPattern,
          fromBeginning: false 
        });
        this.logger.log(`📡 Subscribed to topic: ${topicPattern}`);
      }

      await consumer.run({
        eachMessage: async ({ topic, partition, message }: EachMessagePayload) => {
          try {
            const data = JSON.parse(message.value?.toString() || '{}');
            this.logger.log(`📥 Received message from ${topic}:${partition}`);
            await handler(data);
          } catch (error) {
            this.logger.error(`❌ Error processing message from ${topic}:`, error);
          }
        },
      });

      this.consumers.set(`${topicPattern}-${groupId}`, consumer);
      this.messageHandlers.set(`${topicPattern}-${groupId}`, handler);

    } catch (error) {
      this.logger.error(`❌ Failed to subscribe to ${topicPattern}:`, error);
      throw error;
    }
  }

  async createTopics(topics: string[]) {
    const admin = this.kafka.admin();
    await admin.connect();

    try {
      await admin.createTopics({
        topics: topics.map(topic => ({
          topic,
          numPartitions: 3,
          replicationFactor: 1,
        })),
      });
      this.logger.log(`Topics created: ${topics.join(', ')}`);
    } catch (error) {
      this.logger.warn(`Topics might already exist: ${error.message}`);
    } finally {
      await admin.disconnect();
    }
  }
}