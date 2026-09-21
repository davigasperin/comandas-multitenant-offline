import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  Query,
  Request,
  UseGuards,
  NotFoundException,
  BadRequestException,
  ConflictException,
} from '@nestjs/common';
import * as crypto from 'crypto';
import { AuthGuard } from './auth.guard';
import { TenantGuard } from './tenant.guard';
import { PrismaService } from './prisma.service';
import { OrdersGateway } from './orders.gateway';

interface RequestContext {
  tenantId: string;
  headers: Record<string, string | string[] | undefined>;
}

const VALID_TRANSITIONS: Record<string, string> = {
  open: 'sentToKitchen',
  sentToKitchen: 'delivered',
};

function computePayloadHash(payload: unknown): string {
  return crypto.createHash('sha256').update(JSON.stringify(payload ?? {})).digest('hex');
}

@UseGuards(AuthGuard, TenantGuard)
@Controller('v1/orders')
export class OrdersController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly ordersGateway: OrdersGateway,
  ) {}

  private async checkIdempotency(tenantId: string, key: string | undefined, payload: unknown) {
    if (!key) return null;
    const existing = await this.prisma.idempotencyKey.findUnique({
      where: { tenantId_key: { tenantId, key } },
    });
    if (!existing) return null;
    const currentHash = computePayloadHash(payload);
    if (existing.requestHash && existing.requestHash !== currentHash) {
      throw new ConflictException('Idempotency key reused with different payload');
    }
    return JSON.parse(existing.response);
  }

  private async saveIdempotency(tx: any, tenantId: string, key: string | undefined, payload: unknown, response: unknown) {
    if (!key) return;
    await tx.idempotencyKey.create({
      data: {
        tenantId,
        key,
        requestHash: computePayloadHash(payload),
        response: JSON.stringify(response),
      },
    }).catch(() => {});
  }

  @Get('products')
  async getProducts(@Request() req: RequestContext) {
    const products = await this.prisma.product.findMany({
      where: { tenantId: req.tenantId },
      orderBy: { createdAt: 'desc' },
    });
    return { data: products };
  }

  @Get()
  async getOrders(@Request() req: RequestContext, @Query('status') statusString?: string) {
    let statuses: string[] | undefined;
    if (typeof statusString === 'string' && statusString.trim()) {
      statuses = statusString.split(',').map((s) => s.trim());
    }

    const orders = await this.prisma.order.findMany({
      where: {
        tenantId: req.tenantId,
        ...(statuses ? { status: { in: statuses } } : {}),
      },
      include: { items: true },
      orderBy: { opened_at: 'desc' },
    });
    return { data: orders };
  }

  @Post()
  async createOrder(@Request() req: RequestContext, @Body() body: any) {
    const rawKey = req.headers['x-idempotency-key'];
    const key = Array.isArray(rawKey) ? rawKey[0] : rawKey;

    const cached = await this.checkIdempotency(req.tenantId, key, body);
    if (cached) return cached;

    if (!body || typeof body.table_label !== 'string' || !body.table_label.trim()) {
      throw new BadRequestException('Mesa/Comanda é obrigatória');
    }

    const tableLabel = body.table_label.trim();

    const created = await this.prisma.$transaction(async (tx) => {
      const order = await tx.order.create({
        data: {
          tenantId: req.tenantId,
          table_label: tableLabel,
          status: 'open',
        },
        include: { items: true },
      });

      await this.saveIdempotency(tx, req.tenantId, key, body, order);
      return order;
    });

    this.ordersGateway.emitToTenant(req.tenantId, 'order:created', created);
    return created;
  }

  @Get(':id')
  async getOrderById(@Request() req: RequestContext, @Param('id') id: string) {
    const order = await this.prisma.order.findFirst({
      where: { id, tenantId: req.tenantId },
      include: { items: true },
    });
    if (!order) throw new NotFoundException('Comanda não encontrada');
    return order;
  }

  @Patch(':id/status')
  async updateOrderStatus(
    @Request() req: RequestContext,
    @Param('id') id: string,
    @Body() body: { status: string },
  ) {
    const rawKey = req.headers['x-idempotency-key'];
    const key = Array.isArray(rawKey) ? rawKey[0] : rawKey;

    const cached = await this.checkIdempotency(req.tenantId, key, body);
    if (cached) return cached;

    const nextStatus = body?.status;
    if (!nextStatus || typeof nextStatus !== 'string') {
      throw new BadRequestException('Status é obrigatório');
    }

    const allowedPrevious = Object.entries(VALID_TRANSITIONS).find(([, target]) => target === nextStatus)?.[0];
    if (!allowedPrevious) {
      throw new BadRequestException(`Transição inválida para status ${nextStatus}`);
    }

    const updated = await this.prisma.$transaction(async (tx) => {
      const result = await tx.order.updateMany({
        where: {
          id,
          tenantId: req.tenantId,
          status: allowedPrevious,
        },
        data: {
          status: nextStatus,
        },
      });

      if (result.count === 0) {
        const existing = await tx.order.findFirst({
          where: { id, tenantId: req.tenantId },
        });
        if (!existing) throw new NotFoundException('Comanda não encontrada');
        if (existing.status === nextStatus) {
          return tx.order.findUniqueOrThrow({
            where: { id },
            include: { items: true },
          });
        }
        throw new ConflictException(`Transição de ${existing.status} para ${nextStatus} não permitida`);
      }

      const fresh = await tx.order.findUniqueOrThrow({
        where: { id },
        include: { items: true },
      });

      await this.saveIdempotency(tx, req.tenantId, key, body, fresh);
      return fresh;
    });

    this.ordersGateway.emitToTenant(req.tenantId, 'order:updated', updated);
    return updated;
  }

  @Post(':id/items')
  async addItem(@Request() req: RequestContext, @Param('id') id: string, @Body() body: any) {
    const rawKey = req.headers['x-idempotency-key'];
    const key = Array.isArray(rawKey) ? rawKey[0] : rawKey;

    const cached = await this.checkIdempotency(req.tenantId, key, body);
    if (cached) return cached;

    const order = await this.prisma.order.findFirst({
      where: { id, tenantId: req.tenantId },
    });
    if (!order) throw new NotFoundException('Comanda não encontrada');
    if (order.status === 'closed' || order.status === 'canceled') {
      throw new BadRequestException('Não é possível adicionar itens em comanda finalizada');
    }

    const rawQuantity = Number(body?.quantity);
    if (!Number.isInteger(rawQuantity) || rawQuantity <= 0) {
      throw new BadRequestException('Quantidade deve ser um número inteiro positivo');
    }

    let productName = typeof body?.product_name === 'string' ? body.product_name.trim() : '';
    let unitPrice = 20.0;

    if (typeof body?.product_id === 'string' && body.product_id.trim()) {
      const product = await this.prisma.product.findFirst({
        where: { id: body.product_id, tenantId: req.tenantId },
      });
      if (!product) throw new NotFoundException('Produto não encontrado');
      productName = product.name;
      unitPrice = product.price;
    }

    if (!productName) {
      throw new BadRequestException('Produto é obrigatório');
    }

    const notes = typeof body?.notes === 'string' && body.notes.trim() ? body.notes.trim() : undefined;

    const updated = await this.prisma.$transaction(async (tx) => {
      await tx.orderItem.create({
        data: {
          orderId: id,
          product_name: productName,
          quantity: rawQuantity,
          unit_price: unitPrice,
          notes,
        },
      });

      const fresh = await tx.order.findUniqueOrThrow({
        where: { id },
        include: { items: true },
      });

      await this.saveIdempotency(tx, req.tenantId, key, body, fresh);
      return fresh;
    });

    this.ordersGateway.emitToTenant(req.tenantId, 'order:updated', updated);
    return updated;
  }

  @Post(':id/close')
  async closeOrder(@Request() req: RequestContext, @Param('id') id: string) {
    const rawKey = req.headers['x-idempotency-key'];
    const key = Array.isArray(rawKey) ? rawKey[0] : rawKey;

    const cached = await this.checkIdempotency(req.tenantId, key, {});
    if (cached) return cached;

    const order = await this.prisma.order.findFirst({
      where: { id, tenantId: req.tenantId },
      include: { items: true },
    });
    if (!order) throw new NotFoundException('Comanda não encontrada');
    if (order.status === 'closed') return order;
    if (order.status === 'canceled') {
      throw new BadRequestException('Comanda cancelada não pode ser fechada');
    }

    const updated = await this.prisma.$transaction(async (tx) => {
      const closed = await tx.order.update({
        where: { id },
        data: { status: 'closed' },
        include: { items: true },
      });

      await this.saveIdempotency(tx, req.tenantId, key, {}, closed);
      return closed;
    });

    this.ordersGateway.emitToTenant(req.tenantId, 'order:updated', updated);
    return updated;
  }
}
