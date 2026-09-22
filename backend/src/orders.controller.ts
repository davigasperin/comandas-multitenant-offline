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
import { Prisma } from '@prisma/client';
import { AuthGuard } from './auth.guard';
import { AddItemDto, CloseOrderDto, CreateOrderDto, QueryOrdersDto, SettleOrderDto, UpdateOrderStatusDto } from './dto/orders.dto';
import { calculateBillTotals, validatePaymentsTotal } from './financial.utils';
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

  private getIdempotencyKey(req: RequestContext): string {
    const rawKey = req.headers['x-idempotency-key'];
    const key = Array.isArray(rawKey) ? undefined : rawKey?.trim();
    if (!key) {
      throw new BadRequestException('X-Idempotency-Key é obrigatório e deve ser único');
    }
    return key;
  }

  private async checkIdempotency(tenantId: string, key: string | undefined, payload: unknown) {
    if (!key) return null;
    const existing = await this.prisma.idempotencyKey.findUnique({ where: { tenantId_key: { tenantId, key } } });
    if (!existing) return null;
    const currentHash = computePayloadHash(payload);
    if (existing.requestHash && existing.requestHash !== currentHash) throw new ConflictException('Chave de idempotência já utilizada com payload diferente');
    if (existing.status === 'processing') throw new ConflictException('Chave de idempotência está sendo processada');
    return existing.response ? JSON.parse(existing.response) : null;
  }

  private async saveIdempotency(tx: Prisma.TransactionClient, tenantId: string, key: string | undefined, payload: unknown, response: unknown) {
    if (!key) return;
    await tx.idempotencyKey.create({ data: { tenantId, key, status: 'completed', requestHash: computePayloadHash(payload), response: JSON.stringify(response), completed_at: new Date() } });
  }

  private async executeIdempotent<T>(
    req: RequestContext,
    operation: string,
    payload: unknown,
    mutate: (tx: Prisma.TransactionClient) => Promise<T>,
  ): Promise<{ value: T; replayed: boolean }> {
    const key = this.getIdempotencyKey(req);
    const requestHash = computePayloadHash({
      operation,
      tenantId: req.tenantId,
      userId: req.user?.sub ?? null,
      payload,
    });

    const existing = await this.prisma.idempotencyKey.findUnique({
      where: { tenantId_key: { tenantId: req.tenantId, key } },
    });
    if (existing) {
      if (existing.requestHash !== requestHash) {
        throw new ConflictException('Chave de idempotência já utilizada em outra operação');
      }
      if (existing.status === 'completed' && existing.response) {
        return { value: JSON.parse(existing.response) as T, replayed: true };
      }
      throw new ConflictException('Operação com esta chave ainda está sendo processada');
    }

    try {
      const value = await this.prisma.$transaction(async (tx) => {
        await tx.idempotencyKey.create({
          data: {
            tenantId: req.tenantId,
            key,
            status: 'processing',
            requestHash,
          },
        });
        const result = await mutate(tx);
        await tx.idempotencyKey.update({
          where: { tenantId_key: { tenantId: req.tenantId, key } },
          data: {
            status: 'completed',
            response: JSON.stringify(result),
            completed_at: new Date(),
          },
        });
        return result;
      });
      return { value, replayed: false };
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        const canonical = await this.prisma.idempotencyKey.findUnique({
          where: { tenantId_key: { tenantId: req.tenantId, key } },
        });
        if (canonical?.requestHash !== requestHash) {
          throw new ConflictException('Chave de idempotência já utilizada em outra operação');
        }
        if (canonical?.status === 'completed' && canonical.response) {
          return { value: JSON.parse(canonical.response) as T, replayed: true };
        }
        throw new ConflictException('Operação concorrente ainda está sendo processada');
      }
      throw error;
    }
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
      orderBy: [{ opened_at: 'desc' }, { id: 'desc' }],
    });

    let nextCursor: string | null = null;
    if (orders.length > take) {
      orders.pop();
      nextCursor = orders[orders.length - 1]?.id ?? null;
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
    let tableLabel = body.table_label.trim();
    const userId = req.user?.sub;
    let diningTableId: string | null = null;

    if (body.table_id) {
      const table = await this.prisma.diningTable.findFirst({
        where: { id: body.table_id, tenantId: req.tenantId, active: true },
      });
      if (!table) throw new NotFoundException('Mesa selecionada não encontrada ou inativa');
      diningTableId = table.id;
      if (!tableLabel) tableLabel = table.label;
    }

    const result = await this.executeIdempotent(req, 'POST /v1/orders', body, async (tx) => {
      if (diningTableId) {
        const activeOrderOnTable = await tx.order.findFirst({
          where: {
            tenantId: req.tenantId,
            tableId: diningTableId,
            status: { notIn: ['closed', 'canceled'] },
          },
        });
        if (activeOrderOnTable) {
          throw new ConflictException(`Mesa "${tableLabel}" já possui uma comanda ativa`);
        }
      }

      try {
        return await tx.order.create({
          data: {
            tenantId: req.tenantId,
            tableId: diningTableId,
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
      } catch (error) {
        if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
          throw new ConflictException(`Mesa "${tableLabel}" já está ocupada`);
        }
        throw error;
      }
    });

    if (!result.replayed) this.ordersGateway.emitToTenant(req.tenantId, 'order:created', result.value);
    return result.value;
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
      if (!product.active || !product.available) {
        throw new BadRequestException('Produto inativo ou indisponível não pode ser adicionado ao pedido');
      }
      productName = product.name;
      unitPriceCents = product.price_cents; // Preço canônico do servidor
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

  private async settlementPreview(tenantId: string, id: string, discountCents = 0, serviceFeeBps = 1000) {
    const order = await this.prisma.order.findFirst({
      where: { id, tenantId },
      include: { items: true },
    });
    if (!order) throw new NotFoundException('Comanda não encontrada');
    const subtotalCents = order.items.reduce((total, item) => total + item.quantity * item.unit_price_cents, 0);
    return calculateBillTotals({ subtotalCents, discountCents, serviceFeeBps });
  }

  @Roles('cashier', 'manager')
  @Post(':id/settlement-preview')
  async previewSettlement(@Request() req: RequestContext, @Param('id') id: string, @Body() body: Partial<SettleOrderDto>) {
    const totals = await this.settlementPreview(req.tenantId, id, body.discount_cents ?? 0, body.service_fee_bps ?? 1000);
    return {
      subtotal_cents: totals.subtotalCents,
      discount_cents: totals.discountCents,
      discounted_subtotal_cents: totals.discountedSubtotalCents,
      service_fee_bps: totals.serviceFeeBps,
      service_fee_cents: totals.serviceFeeCents,
      total_cents: totals.totalCents,
    };
  }

  @Roles('cashier', 'manager')
  @Post(':id/settle')
  async settleOrder(@Request() req: RequestContext, @Param('id') id: string, @Body() body: SettleOrderDto) {
    const result = await this.executeIdempotent(req, 'POST /v1/orders/:id/settle', { id, ...body }, async (tx) => {
      const order = await tx.order.findFirst({
        where: { id, tenantId: req.tenantId },
        include: { items: true, payments: true },
      });
      if (!order) throw new NotFoundException('Comanda não encontrada');
      if (order.status === 'closed') {
        if (order.payments.length === 0) throw new ConflictException('Comanda histórica fechada sem pagamentos não pode ser reliquidada');
        return tx.order.findUniqueOrThrow({ where: { id }, include: { items: true, payments: true, history: { orderBy: { changed_at: 'asc' } } } });
      }
      if (order.status === 'canceled') throw new BadRequestException('Comanda cancelada não pode ser liquidada');
      if (body.expected_version !== undefined && order.version !== body.expected_version) {
        throw new ConflictException(`Conflito de concorrência: versão esperada ${body.expected_version}, atual ${order.version}`);
      }

      const subtotalCents = order.items.reduce((total, item) => total + item.quantity * item.unit_price_cents, 0);
      const totals = calculateBillTotals({
        subtotalCents,
        discountCents: body.discount_cents ?? 0,
        serviceFeeBps: body.service_fee_bps ?? 1000,
      });
      const paymentCheck = validatePaymentsTotal(totals.totalCents, body.payments.map((payment) => ({
        method: payment.method as any,
        amountCents: payment.amount_cents,
        tenderedCents: payment.tendered_cents,
      })));

      const closed = await tx.order.updateMany({
        where: { id, tenantId: req.tenantId, status: { in: ['open', 'sentToKitchen', 'delivered'] }, version: order.version },
        data: {
          status: 'closed', version: { increment: 1 }, subtotal_cents: totals.subtotalCents,
          discount_cents: totals.discountCents, service_fee_bps: totals.serviceFeeBps,
          service_fee_cents: totals.serviceFeeCents, total_cents: totals.totalCents,
          settled_at: new Date(), settled_by: req.user?.sub,
          tableId: null, // Libera a ocupação da mesa atomicamente
        },
      });
      if (closed.count !== 1) throw new ConflictException('Falha de concorrência ao liquidar comanda');

      await tx.orderPayment.createMany({
        data: paymentCheck.payments.map((payment) => ({
          orderId: id, method: payment.method, amount_cents: payment.amountCents,
          tendered_cents: payment.tenderedCents, change_cents: payment.changeCents,
        })),
      });
      await tx.orderStatusHistory.create({ data: { orderId: id, from_status: order.status, to_status: 'closed', changed_by: req.user?.sub } });
      return tx.order.findUniqueOrThrow({ where: { id }, include: { items: true, payments: true, history: { orderBy: { changed_at: 'asc' } } } });
    });
    if (!result.replayed) this.ordersGateway.emitToTenant(req.tenantId, 'order:updated', result.value);
    return result.value;
  }

  @Roles('waiter', 'cashier', 'manager')
  @Post(':id/transfer')
  async transferTable(
    @Request() req: RequestContext,
    @Param('id') id: string,
    @Body() body: { target_table_id: string },
  ) {
    const targetTableId = body.target_table_id;
    if (!targetTableId) {
      throw new BadRequestException('target_table_id é obrigatório');
    }

    const updated = await this.prisma.$transaction(async (tx) => {
      const order = await tx.order.findFirst({
        where: { id, tenantId: req.tenantId },
      });
      if (!order) throw new NotFoundException('Comanda não encontrada');
      if (['closed', 'canceled'].includes(order.status)) {
        throw new BadRequestException('Comanda finalizada não pode ser transferida');
      }

      const targetTable = await tx.diningTable.findFirst({
        where: { id: targetTableId, tenantId: req.tenantId, active: true },
      });
      if (!targetTable) throw new NotFoundException('Mesa de destino não encontrada ou inativa');

      const activeOrderOnTarget = await tx.order.findFirst({
        where: {
          tenantId: req.tenantId,
          tableId: targetTableId,
          status: { notIn: ['closed', 'canceled'] },
          id: { not: id },
        },
      });
      if (activeOrderOnTarget) {
        throw new ConflictException(`Mesa "${targetTable.label}" já está ocupada por outra comanda ativa`);
      }

      try {
        await tx.order.update({
          where: { id },
          data: {
            tableId: targetTable.id,
            table_label: targetTable.label,
            version: { increment: 1 },
          },
        });
      } catch (error) {
        if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
          throw new ConflictException(`Conflito ao transferir: mesa "${targetTable.label}" já está ocupada`);
        }
        throw error;
      }

      return tx.order.findUniqueOrThrow({
        where: { id },
        include: { items: true, payments: true, history: { orderBy: { changed_at: 'asc' } } },
      });
    });

    this.ordersGateway.emitToTenant(req.tenantId, 'order:updated', updated);
    return updated;
  }

  @Roles('cashier', 'manager')
  @Post(':id/close')
  async closeOrder(@Request() req: RequestContext, @Param('id') id: string, @Body() body: CloseOrderDto) {
    if (body.payments && body.payments.length > 0) {
      return this.settleOrder(req, id, body as SettleOrderDto);
    }
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
      if (body?.expected_version !== undefined) whereClause.version = body.expected_version;

      const closeResult = await tx.order.updateMany({
        where: whereClause,
        data: { status: 'closed', version: { increment: 1 }, tableId: null },
      });
      if (closeResult.count === 0) {
        const existing = await tx.order.findFirst({
          where: { id, tenantId: req.tenantId },
          include: { items: true, payments: true, history: { orderBy: { changed_at: 'asc' } } },
        });
        if (!existing) throw new NotFoundException('Comanda não encontrada');
        if (existing.status === 'closed') return existing;
        if (existing.status === 'canceled') throw new BadRequestException('Comanda cancelada não pode ser fechada');
        if (body?.expected_version !== undefined && existing.version !== body.expected_version) {
          throw new ConflictException(`Conflito de concorrência: versão esperada ${body.expected_version}, atual ${existing.version}`);
        }
        throw new ConflictException('Falha de concorrência ao fechar comanda');
      }

      await tx.orderStatusHistory.create({
        data: { orderId: id, from_status: null, to_status: 'closed', changed_by: userId },
      });
      const closed = await tx.order.findUniqueOrThrow({
        where: { id },
        include: { items: true, payments: true, history: { orderBy: { changed_at: 'asc' } } },
      });
      await this.saveIdempotency(tx, req.tenantId, key, body, closed);
      return closed;
    });
    this.ordersGateway.emitToTenant(req.tenantId, 'order:updated', updated);
    return updated;
  }
}
