import { registerAs } from '@nestjs/config';

export const kafkaConfig = registerAs('kafka', () => ({
  broker: process.env.KAFKA_BROKER || 'localhost:9092',
  clientId: 'nestjs-cqrs-saga',
  consumerGroupId: 'nestjs-saga-consumer',
  topics: {
    orderEvents: 'order-events',
    paymentEvents: 'payment-events',
    sagaEvents: 'saga-events',
    userEvents: 'user-events',
  },
}));