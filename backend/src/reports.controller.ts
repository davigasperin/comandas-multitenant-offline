import { BadRequestException, Controller, Get, Query, Request, UseGuards } from '@nestjs/common';
import { AuthGuard } from './auth.guard';
import { RequireFeature } from './feature.decorator';
import { FeatureGuard } from './feature.guard';
import { PrismaService } from './prisma.service';
import { Roles } from './roles.decorator';
import { RolesGuard } from './roles.guard';
import { TenantGuard } from './tenant.guard';

interface RequestContext {
  tenantId: string;
}

function range(from?: string, to?: string) {
  const start = from ? new Date(from) : new Date(Date.UTC(new Date().getUTCFullYear(), new Date().getUTCMonth(), 1));
  const end = to ? new Date(to) : new Date();
  if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime()) || start > end) {
    throw new BadRequestException('Período inválido');
  }
  return { start, end };
}

@UseGuards(AuthGuard, TenantGuard, RolesGuard, FeatureGuard)
@Roles('cashier', 'manager')
@Controller('v1/reports')
export class ReportsController {
  constructor(private readonly prisma: PrismaService) {}

  @Get('sales')
  async sales(@Request() req: RequestContext, @Query('from') from?: string, @Query('to') to?: string) {
    const { start, end } = range(from, to);
    const orders = await this.prisma.order.findMany({
      where: { tenantId: req.tenantId, status: 'closed', settled_at: { gte: start, lte: end } },
      include: { payments: true },
    });
    const paymentMethods: Record<string, number> = {};
    for (const order of orders) {
      for (const payment of order.payments) paymentMethods[payment.method] = (paymentMethods[payment.method] ?? 0) + payment.amount_cents;
    }
    return {
      from: start,
      to: end,
      orders: orders.length,
      gross_revenue_cents: orders.reduce((sum, order) => sum + order.subtotal_cents, 0),
      discounts_cents: orders.reduce((sum, order) => sum + order.discount_cents, 0),
      service_fees_cents: orders.reduce((sum, order) => sum + order.service_fee_cents, 0),
      received_cents: orders.reduce((sum, order) => sum + order.total_cents, 0),
      payment_methods: paymentMethods,
    };
  }

  @RequireFeature('finance.accounts_payable')
  @Get('expenses')
  async expenses(
    @Request() req: RequestContext,
    @Query('from') from?: string,
    @Query('to') to?: string,
    @Query('axis') axis = 'competence',
  ) {
    const { start, end } = range(from, to);
    if (!['competence', 'payment'].includes(axis)) throw new BadRequestException('Eixo deve ser competence ou payment');
    const byCategory: Record<string, { category_id: string; category: string; amount_cents: number }> = {};
    if (axis === 'competence') {
      const expenses = await this.prisma.payableExpense.findMany({
        where: { tenantId: req.tenantId, canceled_at: null, competence_date: { gte: start, lte: end } },
        include: { category: true },
      });
      for (const expense of expenses) {
        const row = byCategory[expense.categoryId] ?? { category_id: expense.categoryId, category: expense.category.name, amount_cents: 0 };
        row.amount_cents += expense.amount_cents;
        byCategory[expense.categoryId] = row;
      }
    } else {
      const payments = await this.prisma.expensePayment.findMany({
        where: { paid_at: { gte: start, lte: end }, expense: { tenantId: req.tenantId, canceled_at: null } },
        include: { expense: { include: { category: true } } },
      });
      for (const payment of payments) {
        const expense = payment.expense;
        const row = byCategory[expense.categoryId] ?? { category_id: expense.categoryId, category: expense.category.name, amount_cents: 0 };
        row.amount_cents += payment.amount_cents;
        byCategory[expense.categoryId] = row;
      }
    }
    const categories = Object.values(byCategory).sort((a, b) => b.amount_cents - a.amount_cents);
    return { from: start, to: end, axis, total_cents: categories.reduce((sum, row) => sum + row.amount_cents, 0), categories };
  }

  @RequireFeature('reports.profit_margin')
  @Get('profit-margin')
  async profitMargin(
    @Request() req: RequestContext,
    @Query('from') from?: string,
    @Query('to') to?: string,
    @Query('cmv_mode') cmvMode = 'product_cost',
    @Query('expense_axis') expenseAxis = 'competence',
  ) {
    const { start, end } = range(from, to);
    if (!['product_cost', 'purchases'].includes(cmvMode)) throw new BadRequestException('cmv_mode inválido');
    if (!['competence', 'payment'].includes(expenseAxis)) throw new BadRequestException('expense_axis inválido');

    const orders = await this.prisma.order.findMany({
      where: { tenantId: req.tenantId, status: 'closed', settled_at: { gte: start, lte: end } },
      include: { items: true },
    });
    const revenueCents = orders.reduce((sum, order) => sum + order.subtotal_cents, 0);
    const discountsCents = orders.reduce((sum, order) => sum + order.discount_cents, 0);
    const netRevenueCents = revenueCents - discountsCents;

    let cmvCents = 0;
    if (cmvMode === 'product_cost') {
      cmvCents = orders.reduce(
        (sum, order) => sum + order.items.reduce((itemSum, item) => itemSum + item.quantity * item.unit_cost_cents, 0),
        0,
      );
    } else {
      const aggregate = await this.prisma.purchase.aggregate({
        where: { tenantId: req.tenantId, status: 'confirmed', purchased_at: { gte: start, lte: end } },
        _sum: { total_cents: true },
      });
      cmvCents = aggregate._sum.total_cents ?? 0;
    }

    let expensesCents = 0;
    const expenseCategories: Record<string, { category_id: string; category: string; amount_cents: number }> = {};
    if (expenseAxis === 'competence') {
      const expenses = await this.prisma.payableExpense.findMany({
        where: { tenantId: req.tenantId, canceled_at: null, competence_date: { gte: start, lte: end } },
        include: { category: true },
      });
      for (const expense of expenses) {
        expensesCents += expense.amount_cents;
        const row = expenseCategories[expense.categoryId] ?? { category_id: expense.categoryId, category: expense.category.name, amount_cents: 0 };
        row.amount_cents += expense.amount_cents;
        expenseCategories[expense.categoryId] = row;
      }
    } else {
      const payments = await this.prisma.expensePayment.findMany({
        where: { paid_at: { gte: start, lte: end }, expense: { tenantId: req.tenantId, canceled_at: null } },
        include: { expense: { include: { category: true } } },
      });
      for (const payment of payments) {
        expensesCents += payment.amount_cents;
        const expense = payment.expense;
        const row = expenseCategories[expense.categoryId] ?? { category_id: expense.categoryId, category: expense.category.name, amount_cents: 0 };
        row.amount_cents += payment.amount_cents;
        expenseCategories[expense.categoryId] = row;
      }
    }

    const grossProfitCents = netRevenueCents - cmvCents;
    const operatingResultCents = grossProfitCents - expensesCents;
    return {
      from: start,
      to: end,
      cmv_mode: cmvMode,
      expense_axis: expenseAxis,
      revenue_cents: revenueCents,
      discounts_cents: discountsCents,
      net_revenue_cents: netRevenueCents,
      cmv_cents: cmvCents,
      gross_profit_cents: grossProfitCents,
      expenses_cents: expensesCents,
      operating_result_cents: operatingResultCents,
      estimated: true,
      expense_categories: Object.values(expenseCategories).sort((a, b) => b.amount_cents - a.amount_cents),
    };
  }
}
