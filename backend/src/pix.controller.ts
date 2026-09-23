import {
  BadRequestException,
  Body,
  ConflictException,
  Controller,
  ForbiddenException,
  Headers,
  NotFoundException,
  Param,
  Post,
  Req,
  Request,
  UseGuards,
} from '@nestjs/common';
import type { RawBodyRequest } from '@nestjs/common';
import { createHmac, timingSafeEqual } from 'node:crypto';
import { AuthGuard } from './auth.guard';
import { CreatePixChargeDto, PixWebhookDto } from './dto/management.dto';
import { FeatureGuard } from './feature.guard';
import { calculateBillTotals } from './financial.utils';
import { OrdersGateway } from './orders.gateway';
import { PrismaService } from './prisma.service';
import { Prisma } from '@prisma/client';
import { PixService } from './pix.service';
import { RequireFeature } from './feature.decorator';
import { Roles } from './roles.decorator';
import { RolesGuard } from './roles.guard';
import { TenantGuard } from './tenant.guard';

export function getPixWebhookSecret(provider: string): string | undefined {
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(provider)) return undefined;
  const normalized = provider.toUpperCase().replace(/-/g, '_');
  return process.env[`PIX_WEBHOOK_SECRET_${normalized}`];
}

export function verifyPixWebhookSignature(params: {
  provider: string;
  rawBody: Buffer;
  signature?: string;
  timestamp?: string;
}): void {
  const secret = getPixWebhookSecret(params.provider);
  if (!secret) throw new ForbiddenException('Webhook Pix não autorizado');
  if (!params.signature || !params.timestamp) {
    throw new ForbiddenException('Webhook Pix não autorizado');
  }

  const timestampNum = Number(params.timestamp);
  const now = Math.floor(Date.now() / 1000);
  if (!Number.isInteger(timestampNum) || Math.abs(now - timestampNum) > 300) {
    throw new ForbiddenException('Webhook Pix não autorizado');
  }

  const payload = Buffer.concat([Buffer.from(`${params.timestamp}.`, 'utf8'), params.rawBody]);
  const expectedHex = createHmac('sha256', secret).update(payload).digest('hex');
  const suppliedHex = params.signature.replace(/^sha256=/, '').trim();

  const expectedBuf = Buffer.from(expectedHex, 'hex');
  const suppliedBuf = Buffer.from(suppliedHex, 'hex');
  if (
    expectedBuf.length !== suppliedBuf.length ||
    !timingSafeEqual(expectedBuf, suppliedBuf)
  ) {
    throw new ForbiddenException('Webhook Pix não autorizado');
  }
}

interface RequestContext {
  tenantId: string;
}

@UseGuards(AuthGuard, TenantGuard, RolesGuard, FeatureGuard)
@RequireFeature('pix.dynamic_charge')
@Roles('cashier', 'manager')
@Controller('v1/pix')
export class PixController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly pix: PixService,
  ) {}

  @Post('charges')
  async createCharge(@Request() req: RequestContext, @Body() body: CreatePixChargeDto) {
    const order = await this.prisma.order.findFirst({
      where: { id: body.order_id, tenantId: req.tenantId },
      include: { items: true, pixCharges: { where: { status: 'pending' } } },
    });
    if (!order) throw new NotFoundException('Comanda não encontrada');
    if (order.status === 'closed' || order.status === 'canceled') {
      throw new BadRequestException('Comanda finalizada não pode gerar cobrança Pix');
    }
    if (body.expected_version !== undefined && body.expected_version !== order.version) {
      throw new ConflictException(`Conflito de concorrência: versão atual ${order.version}`);
    }
    if (order.pixCharges.length) return order.pixCharges[0];

    const subtotalCents = order.items.reduce((sum, item) => sum + item.quantity * item.unit_price_cents, 0);
    const discountType = body.discount_type ?? (body.discount_cents !== undefined ? 'fixed' : undefined);
    let discountCents = body.discount_cents ?? 0;
    let discountValue = body.discount_value;
    if (discountType === 'percent') {
      if (discountValue === undefined || discountValue > 10000) throw new BadRequestException('Percentual de desconto inválido');
      discountCents = Math.round((subtotalCents * discountValue) / 10000);
    } else if (discountType === 'fixed') {
      discountCents = discountValue ?? discountCents;
      discountValue = discountCents;
    }
    const totals = calculateBillTotals({
      subtotalCents,
      discountCents,
      serviceFeeBps: body.service_fee_bps ?? 0,
    });
    if (totals.totalCents <= 0) throw new BadRequestException('A cobrança Pix deve possuir valor positivo');

    const externalReference = `order_${order.id}_v${order.version}`;
    const adapterCharge = await this.pix.createCharge({
      amountCents: totals.totalCents,
      externalReference,
      expiresInSeconds: body.expires_in_seconds ?? 900,
    });
    try {
      return await this.prisma.pixCharge.create({
        data: {
          tenantId: req.tenantId,
          orderId: order.id,
          provider: adapterCharge.provider,
          txid: adapterCharge.txid,
          amount_cents: totals.totalCents,
          discount_type: discountType,
          discount_value: discountValue,
          discount_cents: discountCents,
          service_fee_bps: totals.serviceFeeBps,
          qr_code: adapterCharge.qrCode,
          copy_paste: adapterCharge.copyPaste,
          expires_at: adapterCharge.expiresAt,
          provider_payload: JSON.stringify(adapterCharge.raw),
        },
      });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        return this.prisma.pixCharge.findFirstOrThrow({ where: { tenantId: req.tenantId, txid: adapterCharge.txid } });
      }
      throw error;
    }
  }
}

@Controller('v1/pix/webhooks')
export class PixWebhookController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly ordersGateway: OrdersGateway,
  ) {}

  @Post(':provider')
  async receive(
    @Param('provider') provider: string,
    @Req() req: RawBodyRequest<any>,
    @Headers('x-pix-signature') signature: string | undefined,
    @Headers('x-pix-timestamp') timestamp: string | undefined,
    @Body() body: PixWebhookDto,
  ) {
    const rawBody = req?.rawBody ?? Buffer.from(JSON.stringify(body), 'utf8');
    this.assertWebhookSignature(provider, rawBody, signature, timestamp);
    const charge = await this.prisma.pixCharge.findFirst({ where: { provider, txid: body.txid } });
    if (!charge) throw new NotFoundException('Cobrança Pix não encontrada');
    if (body.amount_cents !== undefined && body.amount_cents !== charge.amount_cents) {
      throw new BadRequestException('Valor recebido não corresponde à cobrança');
    }
    if (charge.status === 'paid') return { ok: true, replayed: true };

    if (body.status !== 'paid') {
      await this.prisma.pixCharge.update({ where: { id: charge.id }, data: { status: body.status } });
      return { ok: true, status: body.status };
    }

    const closedOrder = await this.prisma.$transaction(async (tx) => {
      const currentCharge = await tx.pixCharge.findUniqueOrThrow({ where: { id: charge.id } });
      if (currentCharge.status === 'paid') return null;
      const order = await tx.order.findUnique({ where: { id: charge.orderId }, include: { items: true } });
      if (!order) throw new NotFoundException('Comanda da cobrança não encontrada');
      if (order.status === 'closed' || order.status === 'canceled') {
        throw new ConflictException('Comanda já foi finalizada por outro fluxo');
      }
      const subtotalCents = order.items.reduce((sum, item) => sum + item.quantity * item.unit_price_cents, 0);
      const totals = calculateBillTotals({
        subtotalCents,
        discountCents: currentCharge.discount_cents,
        serviceFeeBps: currentCharge.service_fee_bps,
      });
      if (totals.totalCents !== currentCharge.amount_cents) {
        throw new ConflictException('A comanda foi alterada depois da criação do Pix');
      }

      await tx.order.update({
        where: { id: order.id },
        data: {
          status: 'closed',
          version: { increment: 1 },
          subtotal_cents: totals.subtotalCents,
          discount_type: currentCharge.discount_type,
          discount_value: currentCharge.discount_value,
          discount_cents: totals.discountCents,
          service_fee_bps: totals.serviceFeeBps,
          service_fee_cents: totals.serviceFeeCents,
          total_cents: totals.totalCents,
          settled_at: new Date(),
          tableId: null,
        },
      });
      await tx.orderPayment.create({
        data: { orderId: order.id, method: 'pix', amount_cents: totals.totalCents, pixChargeId: charge.id },
      });
      await tx.pixCharge.update({ where: { id: charge.id }, data: { status: 'paid', paid_at: new Date() } });
      await tx.orderStatusHistory.create({ data: { orderId: order.id, from_status: order.status, to_status: 'closed' } });

      const saleByProduct = new Map<string, { quantity: number; unitCostCents: number }>();
      for (const item of order.items) {
        if (!item.productId) continue;
        const sale = saleByProduct.get(item.productId) ?? { quantity: 0, unitCostCents: item.unit_cost_cents };
        sale.quantity += item.quantity;
        saleByProduct.set(item.productId, sale);
      }
      for (const [productId, sale] of saleByProduct) {
        const product = await tx.product.findUnique({ where: { id: productId } });
        if (!product?.stock_controlled) continue;
        await tx.product.update({ where: { id: productId }, data: { stock_quantity: { decrement: sale.quantity } } });
        await tx.stockMovement.create({
          data: {
            tenantId: charge.tenantId,
            productId,
            type: 'sale',
            quantity: new Prisma.Decimal(-sale.quantity),
            unit_cost_cents: sale.unitCostCents,
            reference_type: 'order',
            reference_id: order.id,
          },
        });
      }
      return tx.order.findUniqueOrThrow({ where: { id: order.id }, include: { items: true, payments: true } });
    });
    if (closedOrder) this.ordersGateway.emitToTenant(charge.tenantId, 'order:updated', closedOrder);
    return { ok: true, replayed: closedOrder === null };
  }

  private assertWebhookSignature(
    provider: string,
    rawBody: Buffer,
    signature: string | undefined,
    timestamp: string | undefined,
  ) {
    verifyPixWebhookSignature({ provider, rawBody, signature, timestamp });
  }
}
