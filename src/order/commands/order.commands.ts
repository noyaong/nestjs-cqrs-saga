export class CreateOrderCommand {
  constructor(
    public readonly userId: string,
    public readonly items: Array<{
      productId: string;
      productName: string;
      quantity: number;
      price: number;
    }>,
    public readonly shippingAddress: string,
    public readonly correlationId?: string,
  ) {}
}

export class CancelOrderCommand {
  constructor(
    public readonly orderId: string,
    public readonly userId: string,
    public readonly reason?: string,
    public readonly correlationId?: string,
  ) {}
}

export class ConfirmOrderCommand {
  constructor(
    public readonly orderId: string,
    public readonly paymentId: string,
    public readonly correlationId?: string,
  ) {}
}