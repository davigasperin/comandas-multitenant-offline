import { Body, Controller, Get, Param, Post, Query, Request, UseGuards, NotFoundException, BadRequestException } from '@nestjs/common';
import { AuthGuard } from './auth.guard';
import { TenantGuard } from './tenant.guard';
import { ORDERS, Order, OrderItem, PRODUCTS } from './db';

const idempotencyStore = new Map<string, any>();

@UseGuards(AuthGuard, TenantGuard)
@Controller('v1/orders')
export class OrdersController {
  @Get('products')
  getProducts(@Request() req: any) {
    return { data: PRODUCTS.filter((product) => product.tenantId === req.tenantId) };
  }

  @Get()
  getOrders(@Request() req: any, @Query('status') statusString?: string) {
    const tenantId = req.tenantId;
    let tenantOrders = ORDERS.filter(o => o.tenantId === tenantId);
    
    if (statusString) {
      const statuses = statusString.split(',');
      tenantOrders = tenantOrders.filter(o => statuses.includes(o.status));
    }
    
    return { data: tenantOrders };
  }

  @Post()
  createOrder(@Request() req: any, @Body() body: any) {
    const key = req.headers['x-idempotency-key'] as string;
    if (key && idempotencyStore.has(`${req.tenantId}:${key}`)) {
      return idempotencyStore.get(`${req.tenantId}:${key}`);
    }
    if (!body.table_label || typeof body.table_label !== 'string' || !body.table_label.trim()) {
      throw new BadRequestException('Mesa/Comanda é obrigatória');
    }
    const newOrder: Order = {
      id: `ord_${Math.random().toString(36).substring(2, 9)}`,
      tenantId: req.tenantId,
      table_label: body.table_label.trim(),
      status: 'open',
      opened_at: new Date().toISOString(),
      items: [],
    };
    ORDERS.unshift(newOrder);
    if (key) idempotencyStore.set(`${req.tenantId}:${key}`, newOrder);
    return newOrder;
  }

  @Get(':id')
  getOrderById(@Request() req: any, @Param('id') id: string) {
    const order = ORDERS.find(o => o.id === id && o.tenantId === req.tenantId);
    if (!order) throw new NotFoundException('Comanda não encontrada');
    return order;
  }

  @Post(':id/items')
  addItem(@Request() req: any, @Param('id') id: string, @Body() body: any) {
    const key = req.headers['x-idempotency-key'] as string;
    if (key && idempotencyStore.has(`${req.tenantId}:${key}`)) {
      return idempotencyStore.get(`${req.tenantId}:${key}`);
    }
    const order = ORDERS.find((o) => o.id === id && o.tenantId === req.tenantId);
    if (!order) throw new NotFoundException('Comanda não encontrada');
    if (order.status === 'closed' || order.status === 'canceled') {
      throw new BadRequestException('Não é possível adicionar itens em comanda finalizada');
    }

    const rawQuantity = Number(body.quantity);
    if (!Number.isInteger(rawQuantity) || rawQuantity <= 0) {
      throw new BadRequestException('Quantidade deve ser um número inteiro positivo');
    }

    let productName = typeof body.product_name === 'string' ? body.product_name.trim() : '';
    let unitPrice = 20.0;

    if (body.product_id) {
      const product = PRODUCTS.find(
        (p) => p.id === body.product_id && p.tenantId === req.tenantId,
      );
      if (!product) throw new NotFoundException('Produto não encontrado');
      productName = product.name;
      unitPrice = product.price;
    }

    if (!productName) {
      throw new BadRequestException('Produto é obrigatório');
    }

    const notes = typeof body.notes === 'string' && body.notes.trim() ? body.notes.trim() : undefined;
    const newItem: OrderItem = {
      id: `item_${Math.random().toString(36).substring(2, 9)}`,
      product_name: productName,
      quantity: rawQuantity,
      unit_price: unitPrice,
      notes,
    };

    order.items.push(newItem);
    if (key) idempotencyStore.set(`${req.tenantId}:${key}`, order);
    return order;
  }

  @Post(':id/close')
  closeOrder(@Request() req: any, @Param('id') id: string) {
    const key = req.headers['x-idempotency-key'] as string;
    if (key && idempotencyStore.has(`${req.tenantId}:${key}`)) {
      return idempotencyStore.get(`${req.tenantId}:${key}`);
    }
    const order = ORDERS.find((o) => o.id === id && o.tenantId === req.tenantId);
    if (!order) throw new NotFoundException('Comanda não encontrada');
    if (order.status === 'closed') {
      return order;
    }
    if (order.status === 'canceled') {
      throw new BadRequestException('Comanda cancelada não pode ser fechada');
    }

    order.status = 'closed';
    if (key) idempotencyStore.set(`${req.tenantId}:${key}`, order);
    return order;
  }
}
