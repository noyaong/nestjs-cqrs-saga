# NestJS CQRS Saga

A comprehensive NestJS application implementing CQRS (Command Query Responsibility Segregation) pattern with Saga orchestration for distributed transaction management.

## 🚀 Features

- **CQRS Pattern**: Separation of command and query responsibilities
- **Event Sourcing**: Complete audit trail with event store
- **Saga Orchestration**: Distributed transaction management
- **Domain-Driven Design**: Clean architecture with domain separation
- **PostgreSQL**: Robust data persistence
- **TypeORM**: Advanced ORM with migration support
- **Kafka Integration**: Event-driven microservices communication
- **API Documentation**: Swagger/OpenAPI integration
- **Validation**: Request/response validation with class-validator
- **Docker Support**: Containerized deployment

## 🏗️ Architecture

```
src/
├── auth/           # Authentication & Authorization
├── user/           # User management
├── order/          # Order domain (Commands, Queries, Events)
├── payment/        # Payment processing
├── saga/           # Saga orchestration
├── event-store/    # Event sourcing
├── kafka/          # Message broker integration
├── database/       # Database configuration
└── config/         # Application configuration
```

## 📋 Prerequisites

- Node.js 18+ 
- PostgreSQL 13+
- Docker & Docker Compose (optional)
- Kafka (for event streaming)

## 🛠️ Installation

### 1. Clone the repository
```bash
git clone <repository-url>
cd nestjs-cqrs-saga
```

### 2. Install dependencies
```bash
npm install
```

### 3. Environment Configuration
```bash
cp .env.example .env
```

Edit `.env` file with your database and service configurations:
```env
# Database
DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_USERNAME=postgres
DATABASE_PASSWORD=postgres
DATABASE_NAME=nestjs_cqrs_saga

# JWT
JWT_SECRET=your-secret-key
JWT_EXPIRES_IN=24h

# Kafka
KAFKA_BROKERS=localhost:9092
```

### 4. Database Setup
```bash
# Start PostgreSQL (if using Docker)
docker run --name postgres -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres

# Run migrations
npm run typeorm:migration:run
```

### 5. Start the application
```bash
# Development
npm run start:dev

# Production
npm run build
npm run start:prod
```

## 🔄 CQRS Flow Example

### Order Creation Flow
1. **Command**: `CreateOrderCommand` → `CreateOrderHandler`
2. **Event**: `OrderCreatedEvent` → Event Store
3. **Saga**: Order Processing Saga initiates
4. **Command**: `ProcessPaymentCommand` → Payment Service
5. **Event**: `PaymentProcessedEvent` or `PaymentFailedEvent`
6. **Compensation**: Automatic rollback on failure

### API Usage Example
```bash
# Create Order
POST /orders
{
  "items": [
    {
      "productId": "product-1",
      "productName": "MacBook Pro",
      "quantity": 1,
      "price": 1500000
    }
  ],
  "shippingAddress": "서울시 강남구 테헤란로 123"
}

# Get Orders
GET /orders

# Get Order by ID
GET /orders/:id
```

## 📡 Event Store Queries

```sql
-- View all events for an order
SELECT * FROM event_store 
WHERE "aggregateId" = 'order-uuid-here' 
ORDER BY "occurredAt";

-- View events by correlation ID (Saga tracking)
SELECT * FROM event_store 
WHERE "correlationId" = 'correlation-uuid-here';

-- View events by type
SELECT * FROM event_store 
WHERE "eventType" = 'OrderCreated';
```

## 🐳 Docker Deployment

```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down
```

## 🧪 Testing

```bash
# Unit tests
npm run test

# E2E tests  
npm run test:e2e

# Test coverage
npm run test:cov
```

## 📚 API Documentation

Once the application is running, visit:
- Swagger UI: `http://localhost:3000/api`
- API JSON: `http://localhost:3000/api-json`

## 🔧 Available Scripts

- `npm run start` - Start the application
- `npm run start:dev` - Start in development mode with hot reload
- `npm run start:debug` - Start in debug mode
- `npm run build` - Build the application
- `npm run typeorm:migration:generate` - Generate new migration
- `npm run typeorm:migration:run` - Run pending migrations
- `npm run typeorm:migration:revert` - Revert last migration

## 🌟 Key Components

### Commands
- `CreateOrderCommand` - Creates a new order
- `CancelOrderCommand` - Cancels an existing order
- `ConfirmOrderCommand` - Confirms order after payment
- `ProcessPaymentCommand` - Initiates payment processing

### Events
- `OrderCreatedEvent` - Order creation completed
- `OrderCancelledEvent` - Order cancellation completed
- `PaymentProcessedEvent` - Payment successful
- `PaymentFailedEvent` - Payment failed

### Sagas
- `OrderProcessingSaga` - Orchestrates order → payment → confirmation flow

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/new-feature`
3. Commit changes: `git commit -am 'Add new feature'`
4. Push to branch: `git push origin feature/new-feature`
5. Submit a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

If you encounter any issues or have questions:
1. Check the [Issues](../../issues) page
2. Create a new issue with detailed information
3. Contact the development team

## 🔗 Related Documentation

- [NestJS Documentation](https://docs.nestjs.com/)
- [CQRS Pattern](https://docs.nestjs.com/recipes/cqrs)
- [Event Sourcing](https://martinfowler.com/eaaDev/EventSourcing.html)
- [Saga Pattern](https://microservices.io/patterns/data/saga.html)