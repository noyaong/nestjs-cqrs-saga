import { ApiProperty } from '@nestjs/swagger';
import { OrderStatus } from '../entities/order.entity';

export class OrderResponseDto {
  @ApiProperty({ example: 'order-uuid', description: '주문 ID' })
  id: string;

  @ApiProperty({ example: 'user-uuid', description: '사용자 ID' })
  userId: string;

  @ApiProperty({ example: 1500000, description: '총 금액' })
  totalAmount: number;

  @ApiProperty({ enum: OrderStatus, example: OrderStatus.PENDING, description: '주문 상태' })
  status: OrderStatus;

  @ApiProperty({ 
    description: '주문 상품 목록',
    example: [
      {
        productId: 'product-uuid-1',
        productName: 'MacBook Pro',
        quantity: 1,
        price: 1500000
      }
    ]
  })
  items: Array<{
    productId: string;
    productName: string;
    quantity: number;
    price: number;
  }>;

  @ApiProperty({ example: '서울시 강남구 테헤란로 123', description: '배송 주소' })
  shippingAddress: string;

  @ApiProperty({ example: '2024-01-01T00:00:00.000Z', description: '생성일' })
  createdAt: Date;

  @ApiProperty({ example: '2024-01-01T00:00:00.000Z', description: '수정일' })
  updatedAt: Date;
}