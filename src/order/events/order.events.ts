export class OrderCreatedEvent {
  constructor(
    public readonly orderId: string,
    public readonly userId: string,
    public readonly totalAmount: number,
    public readonly items: Array<{
      productId: string;
      productName: string;
      quantity: number;
      price: number;
    }>,
    public readonly shippingAddress: string,
    public readonly correlationId?: string,
    public readonly occurredAt: Date = new Date(),
  ) {}
}

export class OrderCancelledEvent {
  constructor(
    public readonly orderId: string,
    public readonly userId: string,
    public readonly reason?: string,
    public readonly correlationId?: string,
    public readonly occurredAt: Date = new Date(),
  ) {}
}

export class OrderConfirmedEvent {
  constructor(
    public readonly orderId: string,
    public readonly paymentId: string,
    public readonly totalAmount: number,
    public readonly correlationId?: string,
    public readonly occurredAt: Date = new Date(),
  ) {}
}

export class OrderStatusChangedEvent {
  constructor(
    public readonly orderId: string,
    public readonly previousStatus: string,
    public readonly newStatus: string,
    public readonly correlationId?: string,
    public readonly occurredAt: Date = new Date(),
  ) {}
}