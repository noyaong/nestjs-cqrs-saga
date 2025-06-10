export class PaymentProcessedEvent {
  constructor(
    public readonly paymentId: string,
    public readonly orderId: string,
    public readonly userId: string,
    public readonly amount: number,
    public readonly externalTransactionId: string,
    public readonly correlationId?: string,
    public readonly occurredAt: Date = new Date(),
  ) {}
}

export class PaymentFailedEvent {
  constructor(
    public readonly paymentId: string,
    public readonly orderId: string,
    public readonly userId: string,
    public readonly amount: number,
    public readonly failureReason: string,
    public readonly correlationId?: string,
    public readonly occurredAt: Date = new Date(),
  ) {}
}

export class PaymentRefundedEvent {
  constructor(
    public readonly paymentId: string,
    public readonly orderId: string,
    public readonly refundAmount: number,
    public readonly reason: string,
    public readonly correlationId?: string,
    public readonly occurredAt: Date = new Date(),
  ) {}
}