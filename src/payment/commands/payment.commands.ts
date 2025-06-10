import { PaymentMethod } from '../entities/payment.entity';

export class ProcessPaymentCommand {
  constructor(
    public readonly orderId: string,
    public readonly userId: string,
    public readonly amount: number,
    public readonly method: PaymentMethod,
    public readonly correlationId?: string,
  ) {}
}

export class RefundPaymentCommand {
  constructor(
    public readonly paymentId: string,
    public readonly reason: string,
    public readonly correlationId?: string,
  ) {}
}