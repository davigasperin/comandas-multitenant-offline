import {
  BadRequestException,
  Body,
  ConflictException,
  Controller,
  Get,
  NotFoundException,
  Param,
  Patch,
  Post,
  Query,
  Request,
  UseGuards,
} from '@nestjs/common';
import * as crypto from 'node:crypto';
import { AuthGuard } from './auth.guard';
import { AddItemDto, CloseOrderDto, CreateOrderDto, QueryOrdersDto, UpdateOrderStatusDto } from './dto/orders.dto';
import { OrdersGateway } from './orders.gateway';
import { PrismaService } from './prisma.service';
import { TenantGuard } from './tenant.guard';
import { Roles } from './roles.decorator';
import { RolesGuard } from './roles.guard';

interface RequestContext {
  tenantId: string;
  user?: { sub: string };
  headers: Record<string, string | string[] | undefined>;
}

const VALID_TRANSITIONS: Record<string, string> = {
  open: 'sentToKitchen',
  sentToKitchen: 'delivered',
};

function computePayloadHash(payload: unknown): string {
  return crypto.createHash('sha256').update(JSON.stringify(payload ?? {})).digest('hex');
}

@UseGuards(AuthGuard, TenantGuard, RolesGuard)
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
      throw new ConflictException('Chave de idempotência já utilizada com payload diferente');
    }
    return existing.response ? JSON.parse(existing.response) : null;
  }

  private async saveIdempotency(tx: any, tenantId: string, key: string | undefined, payload: unknown, response: unknown) {
    if (!key) return;
    await tx.idempotencyKey
      .create({
        data: {
          tenantId,
          key,
          requestHash: computePayloadHash(payload),
          response: JSON.stringify(response),
        },
      })
      .catch(() => {});
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
  async getOrders(@Request() req: RequestContext, @Query() query?: QueryOrdersDto) {
    let statuses: string[] | undefined;
    if (typeof query?.status === 'string' && query.status.trim()) {
      statuses = query.status.split(',').map((s) => s.trim()).filter(Boolean);
    }

    const take = Math.min(Math.max(Number(query?.limit ?? 30), 1), 100);
    const cursor = query?.cursor;

    const orders = await this.prisma.order.findMany({
      where: {
        tenantId: req.tenantId,
        ...(statuses && statuses.length ? { status: { in: statuses } } : {}),
      },
      take: take + 1,
      ...(cursor ? { skip: 1, cursor: { id: cursor } } : {}),
      include: { items: true },
      orderBy: { opened_at: 'desc' },
    });

    let nextCursor: string | null = null;
    if (orders.length > take) {
      const nextItem = orders.pop();
      nextCursor = nextItem?.id ?? null;
    }

    return {
      data: orders,
      pagination: {
        limit: take,
        next_cursor: nextCursor,
      },
    };
  }

  @Roles('waiter', 'cashier', 'manager')
  @Post()
  async createOrder(@Request() req: RequestContext, @Body() body: CreateOrderDto) {
    const rawKey = req.headers['x-idempotency-key'];
    const key = Array.isArray(rawKey) ? rawKey[0] : rawKey;

    const cached = await this.checkIdempotency(req.tenantId, key, body);
    if (cached) return cached;

    const tableLabel = body.table_label.trim();
    const userId = req.user?.sub;

    const created = await this.prisma.$transaction(async (tx) => {
      const order = await tx.order.create({
        data: {
          tenantId: req.tenantId,
          table_label: tableLabel,
          status: 'open',
          version: 1,
          history: {
            create: {
              from_status: null,
              to_status: 'open',
              changed_by: userId,
            },
          },
        },
        include: { items: true, history: true },
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
      include: { items: true, history: { orderBy: { changed_at: 'asc' } } },
    });
    if (!order) throw new NotFoundException('Comanda não encontrada');
    return order;
  }

  @Roles('kitchen', 'cashier', 'manager')
  @Patch(':id/status')
  async updateOrderStatus(
    @Request() req: RequestContext,
    @Param('id') id: string,
    @Body() body: UpdateOrderStatusDto,
  ) {
    const rawKey = req.headers['x-idempotency-key'];
    const key = Array.isArray(rawKey) ? rawKey[0] : rawKey;

    const cached = await this.checkIdempotency(req.tenantId, key, body);
    if (cached) return cached;

    const nextStatus = body.status;
    const userId = req.user?.sub;

    const allowedPrevious = Object.entries(VALID_TRANSITIONS).find(([, target]) => target === nextStatus)?.[0];
    if (!allowedPrevious) {
      throw new BadRequestException(`Transição inválida para status ${nextStatus}`);
    }

    const updated = await this.prisma.$transaction(async (tx) => {
      const whereClause: any = {
        id,
        tenantId: req.tenantId,
        status: allowedPrevious,
      };

      if (body.expected_version !== undefined) {
        whereClause.version = body.expected_version;
      }

      const result = await tx.order.updateMany({
        where: whereClause,
        data: {
          status: nextStatus,
          version: { increment: 1 },
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
            include: { items: true, history: { orderBy: { changed_at: 'asc' } } },
          });
        }
        if (body.expected_version !== undefined && existing.version !== body.expected_version) {
          throw new ConflictException(`Conflito de concorrência: versão esperada ${body.expected_version}, versão atual ${existing.version}`);
        }
        throw new ConflictException(`Transição de ${existing.status} para ${nextStatus} não permitida`);
      }

      await tx.orderStatusHistory.create({
        data: {
          orderId: id,
          from_status: allowedPrevious,
          to_status: nextStatus,
          changed_by: userId,
        },
      });

      const fresh = await tx.order.findUniqueOrThrow({
        where: { id },
        include: { items: true, history: { orderBy: { changed_at: 'asc' } } },
      });

      await this.saveIdempotency(tx, req.tenantId, key, body, fresh);
      return fresh;
    });

    this.ordersGateway.emitToTenant(req.tenantId, 'order:updated', updated);
    return updated;
  }

  @Roles('waiter', 'cashier', 'manager')
  @Post(':id/items')
  async addItem(@Request() req: RequestContext, @Param('id') id: string, @Body() body: AddItemDto) {
    const rawKey = req.headers['x-idempotency-key'];
    const key = Array.isArray(rawKey) ? rawKey[0] : rawKey;

    const cached = await this.checkIdempotency(req.tenantId, key, body);
    if (cached) return cached;

    const rawQuantity = body.quantity;
    let productName = typeof body.product_name === 'string' ? body.product_name.trim() : '';
    let unitPriceCents = body.unit_price_cents;

    if (typeof body.product_id === 'string' && body.product_id.trim()) {
      const product = await this.prisma.product.findFirst({
        where: { id: body.product_id, tenantId: req.tenantId },
      });
      if (!product) throw new NotFoundException('Produto não encontrado');
      productName = product.name;
      unitPriceCents = product.price_cents;
    }

    if (!productName) {
      throw new BadRequestException('Produto é obrigatório');
    }

    if (unitPriceCents === undefined) {
      throw new BadRequestException('Preço unitário em centavos é obrigatório quando produto não é vinculado');
    }

    const notes = typeof body.notes === 'string' && body.notes.trim() ? body.notes.trim() : undefined;

    const updated = await this.prisma.$transaction(async (tx) => {
      const whereClause: any = {
        id,
        tenantId: req.tenantId,
        status: 'open',
      };

      if (body.expected_version !== undefined) {
        whereClause.version = body.expected_version;
      }

      const orderUpdate = await tx.order.updateMany({
        where: whereClause,
        data: { version: { increment: 1 } },
      });

      if (orderUpdate.count === 0) {
        const existing = await tx.order.findFirst({ where: { id, tenantId: req.tenantId } });
        if (!existing) throw new NotFoundException('Comanda não encontrada');
        if (existing.status !== 'open') {
          throw new BadRequestException('Não é possível adicionar itens em comanda finalizada ou em preparo');
        }
        if (body.expected_version !== undefined && existing.version !== body.expected_version) {
          throw new ConflictException(`Conflito de concorrência: versão esperada ${body.expected_version}, atual ${existing.version}`);
        }
        throw new ConflictException('Falha de concorrência ao adicionar item');
      }

      await tx.orderItem.create({
        data: {
          orderId: id,
          product_name: productName,
          quantity: rawQuantity,
          unit_price_cents: unitPriceCents,
          notes,
        },
      });

      const fresh = await tx.order.findUniqueOrThrow({
        where: { id },
        include: { items: true, history: { orderBy: { changed_at: 'asc' } } },
      });

      await this.saveIdempotency(tx, req.tenantId, key, body, fresh);
      return fresh;
    });

    this.ordersGateway.emitToTenant(req.tenantId, 'order:updated', updated);
    return updated;
  }

  @Roles('cashier', 'manager')
  @Post(':id/close')
  async closeOrder(@Request() req: RequestContext, @Param('id') id: string, @Body() body: CloseOrderDto) {
    const rawKey = req.headers['x-idempotency-key'];
    const key = Array.isArray(rawKey) ? rawKey[0] : rawKey;

    const cached = await this.checkIdempotency(req.tenantId, key, body);
    if (cached) return cached;

    const userId = req.user?.sub;

    const updated = await this.prisma.$transaction(async (tx) => {
      const whereClause: any = {
        id,
        tenantId: req.tenantId,
        status: { in: ['open', 'sentToKitchen', 'delivered'] },
      };

      if (body?.expected_version !== undefined) {
        whereClause.version = body.expected_version;
      }

      const closeResult = await tx.order.updateMany({
        where: whereClause,
        data: {
          status: 'closed',
          version: { increment: 1 },
        },
      });

      if (closeResult.count === 0) {
        const existing = await tx.order.findFirst({
          where: { id, tenantId: req.tenantId },
          include: { items: true, history: { orderBy: { changed_at: 'asc' } } },
        });
        if (!existing) throw new NotFoundException('Comanda não encontrada');
        if (existing.status === 'closed') {
          return existing;
        }
        if (existing.status === 'canceled') {
          throw new BadRequestException('Comanda cancelada não pode ser fechada');
        }
        if (body?.expected_version !== undefined && existing.version !== body.expected_version) {
          throw new ConflictException(`Conflito de concorrência: versão esperada ${body.expected_version}, atual ${existing.version}`);
        }
        throw new ConflictException('Falha de concorrência ao fechar comanda');
      }

      await tx.orderStatusHistory.create({
        data: {
          orderId: id,
          from_status: null,
          to_status: 'closed',
          changed_by: userId,
        },
      });

      const closed = await tx.order.findUniqueOrThrow({
        where: { id },
        include: { items: true, history: { orderBy: { changed_at: 'asc' } } },
      });

      await this.saveIdempotency(tx, req.tenantId, key, body, closed);
      return closed;
    });

    this.ordersGateway.emitToTenant(req.tenantId, 'order:updated', updated);
    return updated;
  }
}
