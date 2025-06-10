import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Kafka, Producer, Consumer, EachMessagePayload } from 'kafkajs';

@Injectable()
export class KafkaService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(KafkaService.name);
  private kafka: Kafka;
  private producer: Producer;
  private consumers: Map<string, Consumer> = new Map();

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

  async publish(topic: string, message: any, key?: string) {
    try {
      this.logger.log(`Attempting to publish to topic: ${topic}`);
      
      const result = await this.producer.send({
        topic,
        messages: [
          {
            key: key || Date.now().toString(),
            value: JSON.stringify(message),
            timestamp: Date.now().toString(),
          },
        ],
      });
      
      this.logger.log(`Message published successfully to ${topic}`);
      this.logger.debug(`Message content: ${JSON.stringify(message)}`);
      return result;
    } catch (error) {
      this.logger.error(`Failed to publish message to ${topic}:`, error.message);
      this.logger.error(`Error stack:`, error.stack);
      throw error;
    }
  }

  async subscribe(
    topic: string,
    groupId: string,
    messageHandler: (payload: EachMessagePayload) => Promise<void>,
  ) {
    const consumer = this.kafka.consumer({ groupId });
    
    await consumer.connect();
    await consumer.subscribe({ topic, fromBeginning: false });
    
    await consumer.run({
      eachMessage: async (payload) => {
        try {
          this.logger.log(`Received message from ${topic}: ${payload.message.value?.toString()}`);
          await messageHandler(payload);
        } catch (error) {
          this.logger.error(`Error processing message from ${topic}:`, error);
        }
      },
    });

    this.consumers.set(groupId, consumer);
    this.logger.log(`Kafka consumer subscribed to ${topic} with group ${groupId}`);
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