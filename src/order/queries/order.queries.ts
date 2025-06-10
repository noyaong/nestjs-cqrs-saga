export class GetOrderByIdQuery {
  constructor(
    public readonly orderId: string,
    public readonly userId?: string, // 권한 확인용
  ) {}
}

export class GetOrdersByUserIdQuery {
  constructor(
    public readonly userId: string,
    public readonly page: number = 1,
    public readonly limit: number = 10,
    public readonly status?: string,
  ) {}
}

export class GetOrdersQuery {
  constructor(
    public readonly page: number = 1,
    public readonly limit: number = 10,
    public readonly status?: string,
    public readonly userId?: string,
  ) {}
}