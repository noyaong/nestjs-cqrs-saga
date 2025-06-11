import {
  Controller,
  Post,
  Get,
  Put,
  Delete,
  Body,
  Param,
  Query,
  UseGuards,
  Request,
  ParseUUIDPipe,
  ParseIntPipe,
  Logger,
} from '@nestjs/common';
import { CommandBus, QueryBus } from '@nestjs/cqrs';
import {
  ApiTags,
  ApiOperation,
  ApiResponse,
  ApiBearerAuth,
  ApiParam,
  ApiQuery,
} from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
  import { CreateOrderDto } from './dto/create-order.dto';
  import { OrderResponseDto } from './dto/order-response.dto';
import { CreateOrderCommand, CancelOrderCommand, ConfirmOrderCommand } from './commands/order.commands';
import { GetOrderByIdQuery, GetOrdersByUserIdQuery, GetOrdersQuery } from './queries/order.queries';
import { Order, OrderStatus } from './entities/order.entity';
import { createHash } from 'crypto';

@ApiTags('Orders')
@Controller('orders')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class OrderController {
  private readonly logger = new Logger(OrderController.name);
  
  constructor(
    private readonly commandBus: CommandBus,
    private readonly queryBus: QueryBus,
  ) {}

  @Post()
  @ApiOperation({ summary: '새 주문 생성' })
  @ApiResponse({
    status: 201,
    description: '주문 생성 성공',
    type: OrderResponseDto,
  })
  async createOrder(
    @Body() createOrderDto: CreateOrderDto,
    @Request() req,
  ): Promise<OrderResponseDto> {
    // 상품 정보 기반 idempotency key 생성
    let idempotencyKey = createOrderDto.idempotencyKey;
    
    console.log(`🔍 FORCED LOG: received idempotencyKey = "${idempotencyKey}"`);
    console.log(`🔍 FORCED LOG: condition !idempotencyKey = ${!idempotencyKey}`);
    
    if (!idempotencyKey) {
      // 상품 ID만으로 솔드아웃 판단 (수량/가격 무관)
      const productData = createOrderDto.items
        .map(item => item.productId || item.productName)
        .sort() // 순서에 관계없이 같은 해시 생성
        .join('|');
      
      console.log(`🔍 DEBUG Controller: productData = "${productData}"`);
      console.log(`🔍 DEBUG Controller: hash input = "SOLDOUT:${productData}"`);
      
      // 솔드아웃 개념: 상품 ID만으로 글로벌 중복 방지
      idempotencyKey = createHash('sha256')
        .update(`SOLDOUT:${productData}`)
        .digest('hex');
        
      console.log(`🔍 DEBUG Controller: calculated idempotencyKey = ${idempotencyKey}`);
    }
    
    console.log(`🔍 DEBUG Controller: final idempotencyKey passed to Command = ${idempotencyKey}`);

    const command = new CreateOrderCommand(
      req.user.id,
      createOrderDto.items,
      createOrderDto.shippingAddress,
      idempotencyKey,
    );

    const order: Order = await this.commandBus.execute(command);
    
    return {
      id: order.id,
      userId: order.userId,
      totalAmount: order.totalAmount,
      status: order.status,
      items: order.items,
      shippingAddress: order.shippingAddress,
      createdAt: order.createdAt,
      updatedAt: order.updatedAt,
    };
  }

  @Get()
  @ApiOperation({ summary: '내 주문 목록 조회' })
  @ApiQuery({ name: 'page', required: false, example: 1 })
  @ApiQuery({ name: 'limit', required: false, example: 10 })
  @ApiQuery({ name: 'status', required: false, enum: OrderStatus })
  @ApiResponse({
    status: 200,
    description: '주문 목록 조회 성공',
  })
  async getMyOrders(
    @Request() req,
    @Query('page', new ParseIntPipe({ optional: true })) page: number = 1,
    @Query('limit', new ParseIntPipe({ optional: true })) limit: number = 10,
    @Query('status') status?: OrderStatus,
  ) {
    const query = new GetOrdersByUserIdQuery(req.user.id, page, limit, status);
    const result = await this.queryBus.execute(query);
    
    return {
      orders: result.orders.map(order => ({
        id: order.id,
        userId: order.userId,
        totalAmount: order.totalAmount,
        status: order.status,
        items: order.items,
        shippingAddress: order.shippingAddress,
        createdAt: order.createdAt,
        updatedAt: order.updatedAt,
      })),
      total: result.total,
      page,
      limit,
      totalPages: Math.ceil(result.total / limit),
    };
  }

  @Get(':id')
  @ApiOperation({ summary: '주문 상세 조회' })
  @ApiParam({ name: 'id', description: '주문 ID' })
  @ApiResponse({
    status: 200,
    description: '주문 조회 성공',
    type: OrderResponseDto,
  })
  async getOrderById(
    @Param('id', ParseUUIDPipe) id: string,
    @Request() req,
  ): Promise<OrderResponseDto> {
    const query = new GetOrderByIdQuery(id, req.user.id);
    const order: Order = await this.queryBus.execute(query);
    
    return {
      id: order.id,
      userId: order.userId,
      totalAmount: order.totalAmount,
      status: order.status,
      items: order.items,
      shippingAddress: order.shippingAddress,
      createdAt: order.createdAt,
      updatedAt: order.updatedAt,
    };
  }

  @Delete(':id')
  @ApiOperation({ summary: '주문 취소' })
  @ApiParam({ name: 'id', description: '주문 ID' })
  @ApiResponse({
    status: 200,
    description: '주문 취소 성공',
  })
  async cancelOrder(
    @Param('id', ParseUUIDPipe) id: string,
    @Request() req,
    @Body('reason') reason?: string,
  ) {
    const command = new CancelOrderCommand(id, req.user.id, reason);
    await this.commandBus.execute(command);
    
    return {
      message: '주문이 취소되었습니다.',
      orderId: id,
    };
  }

  @Put(':id/confirm')
  @ApiOperation({ summary: '주문 확인 (결제 완료 후)' })
  @ApiParam({ name: 'id', description: '주문 ID' })
  @ApiResponse({
    status: 200,
    description: '주문 확인 성공',
  })
  async confirmOrder(
    @Param('id', ParseUUIDPipe) id: string,
    @Body('paymentId') paymentId: string,
  ) {
    const command = new ConfirmOrderCommand(id, paymentId);
    await this.commandBus.execute(command);
    
    return {
      message: '주문이 확인되었습니다.',
      orderId: id,
      paymentId,
    };
  }

  // 테스트용 엔드포인트 (인증으로 주문 생성)
  @Post('test/create')
  @ApiOperation({ summary: '테스트용 주문 생성' })
  @ApiResponse({
    status: 201,
    description: '테스트 주문 생성 성공',
    type: OrderResponseDto,
  })
  async createTestOrder(
    @Body() createOrderDto: CreateOrderDto,
    @Request() req,
  ): Promise<OrderResponseDto> {
    // 실제 인증된 사용자 ID 사용
    const userId = req.user.id;
    
    // 상품 정보 기반 idempotency key 생성
    let idempotencyKey = createOrderDto.idempotencyKey;
    
    if (!idempotencyKey) {
      // 상품 ID만으로 솔드아웃 판단 (수량/가격 무관)
      const productData = createOrderDto.items
        .map(item => item.productId || item.productName)
        .sort() // 순서에 관계없이 같은 해시 생성
        .join('|');
      
      // 솔드아웃 개념: 상품 ID만으로 글로벌 중복 방지
      idempotencyKey = createHash('sha256')
        .update(`SOLDOUT:${productData}`)
        .digest('hex');
    }
    
    const command = new CreateOrderCommand(
      userId,
      createOrderDto.items,
      createOrderDto.shippingAddress,
      idempotencyKey,
    );

    const order: Order = await this.commandBus.execute(command);
    
    return {
      id: order.id,
      userId: order.userId,
      totalAmount: order.totalAmount,
      status: order.status,
      items: order.items,
      shippingAddress: order.shippingAddress,
      createdAt: order.createdAt,
      updatedAt: order.updatedAt,
    };
  }
}