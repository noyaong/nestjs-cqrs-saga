import { ApiProperty } from '@nestjs/swagger';
import { IsArray, IsNumber, IsString, IsUUID, ValidateNested, Min, IsOptional } from 'class-validator';
import { Type } from 'class-transformer';

export class OrderItemDto {
  @ApiProperty({ example: 'product-123', description: '상품 ID' })
  @IsString()
  productId: string;

  @ApiProperty({ example: 'MacBook Pro', description: '상품명' })
  @IsString()
  productName: string;

  @ApiProperty({ example: 2, description: '수량' })
  @IsNumber()
  @Min(1)
  quantity: number;

  @ApiProperty({ example: 1500000, description: '단가' })
  @IsNumber()
  @Min(0)
  price: number;
}

export class CreateOrderDto {
  @ApiProperty({ 
    type: [OrderItemDto], 
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
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => OrderItemDto)
  items: OrderItemDto[];

  @ApiProperty({ 
    example: '서울시 강남구 테헤란로 123',
    description: '배송 주소'
  })
  @IsString()
  shippingAddress: string;

  @ApiProperty({
    example: 'idempotency-key-123',
    description: '중복 방지를 위한 Idempotency 키 (선택사항)',
    required: false,
  })
  @IsOptional()
  @IsString()
  idempotencyKey?: string;
}