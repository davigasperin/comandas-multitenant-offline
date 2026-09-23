import {
  BadRequestException,
  Body,
  ConflictException,
  Controller,
  Delete,
  ForbiddenException,
  Get,
  NotFoundException,
  Param,
  Patch,
  Post,
  Query,
  Request,
  UseGuards,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AuthGuard } from './auth.guard';
import {
  AdjustStockDto,
  CreateExpenseCategoryDto,
  CreateExpenseDto,
  CreateExpensePaymentDto,
  CreatePurchaseDto,
  CreateRecurringExpenseDto,
  CreateSupplierDto,
  GenerateRecurringExpensesDto,
  UpdateExpenseCategoryDto,
  UpdateExpenseDto,
  UpdateSupplierDto,
} from './dto/management.dto';
import { RequireFeature } from './feature.decorator';
import { FeatureGuard } from './feature.guard';
import { executeIdempotent, getIdempotencyKey } from './idempotency.utils';
import { pageArgs, pageResult } from './pagination';
import { PrismaService } from './prisma.service';
import { Roles } from './roles.decorator';
import { RolesGuard } from './roles.guard';
import { TenantGuard } from './tenant.guard';

interface RequestContext {
  tenantId: string;
  user?: { sub: string };
  headers?: Record<string, string | string[] | undefined>;
}

function parseDate(value: string, field: string): Date {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) throw new BadRequestException(`${field} inválida`);
  return parsed;
}

function monthStart(value: Date): Date {
  return new Date(Date.UTC(value.getUTCFullYear(), value.getUTCMonth(), 1));
}

function dueDateForMonth(competence: Date, dueDay: number): Date {
  const lastDay = new Date(Date.UTC(competence.getUTCFullYear(), competence.getUTCMonth() + 1, 0)).getUTCDate();
  return new Date(Date.UTC(competence.getUTCFullYear(), competence.getUTCMonth(), Math.min(dueDay, lastDay)));
}

function withExpenseStatus<T extends { amount_cents: number; due_date: Date; canceled_at: Date | null; payments: Array<{ amount_cents: number }> }>(expense: T) {
  const paidCents = expense.payments.reduce((sum, payment) => sum + payment.amount_cents, 0);
  const balanceCents = Math.max(0, expense.amount_cents - paidCents);
  const status = expense.canceled_at
    ? 'canceled'
    : balanceCents === 0
      ? 'paid'
      : paidCents > 0
        ? 'partially_paid'
        : expense.due_date.getTime() < Date.now()
          ? 'overdue'
          : 'pending';
  return { ...expense, paid_cents: paidCents, balance_cents: balanceCents, status };
}

@UseGuards(AuthGuard, TenantGuard, RolesGuard)
@Controller('v1/suppliers')
export class SuppliersController {
  constructor(private readonly prisma: PrismaService) {}

  @Get()
  async list(@Request() req: RequestContext, @Query('active') active?: string, @Query('limit') limit?: string, @Query('cursor') cursor?: string) {
    const rows = await this.prisma.supplier.findMany({
      where: { tenantId: req.tenantId, ...(active === undefined ? {} : { active: active === 'true' }) },
      orderBy: [{ name: 'asc' }, { id: 'asc' }],
      ...pageArgs(limit, cursor),
    });
    return pageResult(rows, limit);
  }

  @Roles('manager')
  @Post()
  async create(@Request() req: RequestContext, @Body() body: CreateSupplierDto) {
    const key = getIdempotencyKey(req.headers ?? {});
    const result = await executeIdempotent(
      this.prisma,
      req.tenantId,
      key,
      'POST /v1/suppliers',
      body,
      req.user?.sub,
      async (tx) => {
        return tx.supplier.create({
          data: { tenantId: req.tenantId, ...body, name: body.name.trim() },
        });
      },
    );
    return result.value;
  }

  @Roles('manager')
  @Patch(':id')
  async update(@Request() req: RequestContext, @Param('id') id: string, @Body() body: UpdateSupplierDto) {
    const existing = await this.prisma.supplier.findFirst({ where: { id, tenantId: req.tenantId } });
    if (!existing) throw new NotFoundException('Fornecedor não encontrado');
    return this.prisma.supplier.update({
      where: { id },
      data: { ...body, ...(body.name ? { name: body.name.trim() } : {}) },
    });
  }
}

@UseGuards(AuthGuard, TenantGuard, RolesGuard, FeatureGuard)
@RequireFeature('finance.accounts_payable')
@Controller('v1/finance')
export class FinanceController {
  constructor(private readonly prisma: PrismaService) {}

  @Get('expense-categories')
  async listCategories(@Request() req: RequestContext) {
    return { data: await this.prisma.expenseCategory.findMany({ where: { tenantId: req.tenantId }, orderBy: { name: 'asc' } }) };
  }

  @Roles('manager')
  @Post('expense-categories')
  createCategory(@Request() req: RequestContext, @Body() body: CreateExpenseCategoryDto) {
    return this.prisma.expenseCategory.create({ data: { tenantId: req.tenantId, name: body.name.trim() } });
  }

  @Roles('manager')
  @Patch('expense-categories/:id')
  async updateCategory(@Request() req: RequestContext, @Param('id') id: string, @Body() body: UpdateExpenseCategoryDto) {
    const existing = await this.prisma.expenseCategory.findFirst({ where: { id, tenantId: req.tenantId } });
    if (!existing) throw new NotFoundException('Categoria de despesa não encontrada');
    return this.prisma.expenseCategory.update({ where: { id }, data: { ...body, ...(body.name ? { name: body.name.trim() } : {}) } });
  }

  @Get('expenses')
  async listExpenses(
    @Request() req: RequestContext,
    @Query('from') from?: string,
    @Query('to') to?: string,
    @Query('status') status?: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    const expenses = await this.prisma.payableExpense.findMany({
      where: {
        tenantId: req.tenantId,
        ...(from || to ? { due_date: { ...(from ? { gte: parseDate(from, 'from') } : {}), ...(to ? { lte: parseDate(to, 'to') } : {}) } } : {}),
      },
      include: { supplier: true, category: true, payments: { orderBy: { paid_at: 'asc' } } },
      orderBy: [{ due_date: 'asc' }, { createdAt: 'desc' }, { id: 'desc' }],
      ...pageArgs(limit, cursor),
    });
    const data = status ? expenses.map(withExpenseStatus).filter((expense) => expense.status === status) : expenses.map(withExpenseStatus);
    return pageResult(data, limit);
  }

  @Roles('cashier', 'manager')
  @Post('expenses')
  async createExpense(@Request() req: RequestContext, @Body() body: CreateExpenseDto) {
    await this.assertFinanceReferences(req.tenantId, body.category_id, body.supplier_id);
    const key = getIdempotencyKey(req.headers ?? {});
    const result = await executeIdempotent(
      this.prisma,
      req.tenantId,
      key,
      'POST /v1/finance/expenses',
      body,
      req.user?.sub,
      async (tx) => {
        const expense = await tx.payableExpense.create({
          data: {
            tenantId: req.tenantId,
            supplierId: body.supplier_id,
            categoryId: body.category_id,
            description: body.description.trim(),
            amount_cents: body.amount_cents,
            due_date: parseDate(body.due_date, 'due_date'),
            competence_date: monthStart(parseDate(body.competence_date, 'competence_date')),
            notes: body.notes,
            created_by: req.user?.sub,
          },
          include: { supplier: true, category: true, payments: true },
        });
        return withExpenseStatus(expense);
      },
    );
    return result.value;
  }

  @Roles('cashier', 'manager')
  @Patch('expenses/:id')
  async updateExpense(@Request() req: RequestContext, @Param('id') id: string, @Body() body: UpdateExpenseDto) {
    const existing = await this.prisma.payableExpense.findFirst({ where: { id, tenantId: req.tenantId, canceled_at: null }, include: { payments: true } });
    if (!existing) throw new NotFoundException('Despesa não encontrada');
    if (body.category_id || body.supplier_id) {
      await this.assertFinanceReferences(req.tenantId, body.category_id ?? existing.categoryId, body.supplier_id);
    }
    const paid = existing.payments.reduce((sum, payment) => sum + payment.amount_cents, 0);
    if (body.amount_cents !== undefined && body.amount_cents < paid) {
      throw new BadRequestException('O valor da despesa não pode ser menor que o total já pago');
    }
    const expense = await this.prisma.payableExpense.update({
      where: { id },
      data: {
        supplierId: body.supplier_id,
        categoryId: body.category_id,
        description: body.description?.trim(),
        amount_cents: body.amount_cents,
        due_date: body.due_date ? parseDate(body.due_date, 'due_date') : undefined,
        competence_date: body.competence_date ? monthStart(parseDate(body.competence_date, 'competence_date')) : undefined,
        notes: body.notes,
      },
      include: { supplier: true, category: true, payments: true },
    });
    return withExpenseStatus(expense);
  }

  @Roles('cashier', 'manager')
  @Post('expenses/:id/payments')
  async payExpense(@Request() req: RequestContext, @Param('id') id: string, @Body() body: CreateExpensePaymentDto) {
    const key = getIdempotencyKey(req.headers ?? {});
    const result = await executeIdempotent(
      this.prisma,
      req.tenantId,
      key,
      `POST /v1/finance/expenses/${id}/payments`,
      body,
      req.user?.sub,
      async (tx) => {
        const expense = await tx.payableExpense.findFirst({ where: { id, tenantId: req.tenantId, canceled_at: null }, include: { payments: true } });
        if (!expense) throw new NotFoundException('Despesa não encontrada');
        const paid = expense.payments.reduce((sum, payment) => sum + payment.amount_cents, 0);
        if (paid + body.amount_cents > expense.amount_cents) throw new BadRequestException('Pagamento excede o saldo da despesa');
        await tx.expensePayment.create({
          data: {
            expenseId: id,
            amount_cents: body.amount_cents,
            paid_at: parseDate(body.paid_at, 'paid_at'),
            payment_method: body.payment_method,
            notes: body.notes,
            created_by: req.user?.sub,
          },
        });
        const updated = await tx.payableExpense.findUniqueOrThrow({ where: { id }, include: { supplier: true, category: true, payments: true } });
        return withExpenseStatus(updated);
      },
    );
    return result.value;
  }

  @Roles('manager')
  @Delete('expenses/:id')
  async cancelExpense(@Request() req: RequestContext, @Param('id') id: string) {
    const existing = await this.prisma.payableExpense.findFirst({ where: { id, tenantId: req.tenantId } });
    if (!existing) throw new NotFoundException('Despesa não encontrada');
    return this.prisma.payableExpense.update({ where: { id }, data: { canceled_at: new Date() } });
  }

  @Get('recurring-expenses')
  async listRecurring(@Request() req: RequestContext) {
    return { data: await this.prisma.recurringExpenseTemplate.findMany({ where: { tenantId: req.tenantId }, include: { supplier: true, category: true }, orderBy: { description: 'asc' } }) };
  }

  @Roles('manager')
  @Post('recurring-expenses')
  async createRecurring(@Request() req: RequestContext, @Body() body: CreateRecurringExpenseDto) {
    await this.assertFinanceReferences(req.tenantId, body.category_id, body.supplier_id);
    return this.prisma.recurringExpenseTemplate.create({
      data: {
        tenantId: req.tenantId,
        supplierId: body.supplier_id,
        categoryId: body.category_id,
        description: body.description.trim(),
        amount_cents: body.amount_cents,
        due_day: body.due_day,
        start_date: parseDate(body.start_date, 'start_date'),
        end_date: body.end_date ? parseDate(body.end_date, 'end_date') : undefined,
      },
    });
  }

  @Roles('manager')
  @Post('recurring-expenses/generate')
  async generateRecurring(@Request() req: RequestContext, @Body() body: GenerateRecurringExpensesDto) {
    const competence = monthStart(parseDate(body.competence, 'competence'));
    const templates = await this.prisma.recurringExpenseTemplate.findMany({
      where: {
        tenantId: req.tenantId,
        active: true,
        start_date: { lte: dueDateForMonth(competence, 31) },
        OR: [{ end_date: null }, { end_date: { gte: competence } }],
      },
    });
    let created = 0;
    for (const template of templates) {
      try {
        await this.prisma.payableExpense.create({
          data: {
            tenantId: req.tenantId,
            supplierId: template.supplierId,
            categoryId: template.categoryId,
            recurringTemplateId: template.id,
            description: template.description,
            amount_cents: template.amount_cents,
            competence_date: competence,
            due_date: dueDateForMonth(competence, template.due_day),
            created_by: req.user?.sub,
          },
        });
        created += 1;
      } catch (error) {
        if (!(error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002')) throw error;
      }
    }
    return { competence, templates: templates.length, created, skipped: templates.length - created };
  }

  private async assertFinanceReferences(tenantId: string, categoryId: string, supplierId?: string) {
    const category = await this.prisma.expenseCategory.findFirst({ where: { id: categoryId, tenantId, active: true } });
    if (!category) throw new BadRequestException('Categoria de despesa inválida');
    if (supplierId) {
      const supplier = await this.prisma.supplier.findFirst({ where: { id: supplierId, tenantId, active: true } });
      if (!supplier) throw new BadRequestException('Fornecedor inválido');
    }
  }
}

@UseGuards(AuthGuard, TenantGuard, RolesGuard)
@Controller('v1/inventory')
export class InventoryController {
  constructor(private readonly prisma: PrismaService) {}

  @Get('stock')
  async stock(@Request() req: RequestContext, @Query('limit') limit?: string, @Query('cursor') cursor?: string) {
    const rows = await this.prisma.product.findMany({
      where: { tenantId: req.tenantId, stock_controlled: true },
      select: { id: true, name: true, sku: true, unit: true, cost_cents: true, stock_quantity: true, minimum_stock: true, active: true },
      orderBy: [{ name: 'asc' }, { id: 'asc' }],
      ...pageArgs(limit, cursor),
    });
    return pageResult(rows, limit);
  }

  @Get('movements')
  async movements(@Request() req: RequestContext, @Query('product_id') productId?: string) {
    return {
      data: await this.prisma.stockMovement.findMany({
        where: { tenantId: req.tenantId, ...(productId ? { productId } : {}) },
        include: { product: { select: { id: true, name: true, unit: true } } },
        orderBy: { occurred_at: 'desc' },
        take: 500,
      }),
    };
  }

  @Roles('manager')
  @Post('products/:id/adjust')
  async adjust(@Request() req: RequestContext, @Param('id') id: string, @Body() body: AdjustStockDto) {
    if (body.quantity === 0) throw new BadRequestException('Quantidade do ajuste não pode ser zero');
    const absolute = new Prisma.Decimal(Math.abs(body.quantity));
    const signed = body.type === 'adjustment_out' ? absolute.negated() : absolute;
    const key = getIdempotencyKey(req.headers ?? {});
    const result = await executeIdempotent(
      this.prisma,
      req.tenantId,
      key,
      `POST /v1/inventory/products/${id}/adjust`,
      body,
      req.user?.sub,
      async (tx) => {
        const product = await tx.product.findFirst({ where: { id, tenantId: req.tenantId, stock_controlled: true } });
        if (!product) throw new NotFoundException('Produto com controle de estoque não encontrado');
        const updated = await tx.product.update({
          where: { id },
          data: {
            stock_quantity: { increment: signed },
            ...(body.unit_cost_cents !== undefined ? { cost_cents: body.unit_cost_cents } : {}),
          },
        });
        const movement = await tx.stockMovement.create({
          data: {
            tenantId: req.tenantId,
            productId: id,
            type: body.type,
            quantity: signed,
            unit_cost_cents: body.unit_cost_cents,
            notes: body.notes,
            created_by: req.user?.sub,
          },
        });
        return { product: updated, movement };
      },
    );
    return result.value;
  }
}

@UseGuards(AuthGuard, TenantGuard, RolesGuard)
@Controller('v1/purchases')
export class PurchasesController {
  constructor(private readonly prisma: PrismaService) {}

  @Get()
  async list(@Request() req: RequestContext, @Query('limit') limit?: string, @Query('cursor') cursor?: string) {
    const rows = await this.prisma.purchase.findMany({
      where: { tenantId: req.tenantId },
      include: { supplier: true, items: { include: { product: true } }, payableExpense: true },
      orderBy: [{ purchased_at: 'desc' }, { id: 'desc' }],
      ...pageArgs(limit, cursor),
    });
    return pageResult(rows, limit);
  }

  @Roles('manager')
  @Post()
  async create(@Request() req: RequestContext, @Body() body: CreatePurchaseDto) {
    if (!body.items.length) throw new BadRequestException('A compra deve conter ao menos um item');
    if (new Set(body.items.map((item) => item.product_id)).size !== body.items.length) {
      throw new BadRequestException('Não repita o mesmo produto; consolide a quantidade em um item');
    }
    const productIds = body.items.map((item) => item.product_id);
    const products = await this.prisma.product.findMany({ where: { tenantId: req.tenantId, id: { in: productIds } } });
    if (products.length !== productIds.length) throw new BadRequestException('Um ou mais produtos não pertencem ao estabelecimento');
    if (body.supplier_id) {
      const supplier = await this.prisma.supplier.findFirst({ where: { id: body.supplier_id, tenantId: req.tenantId, active: true } });
      if (!supplier) throw new BadRequestException('Fornecedor inválido');
    }
    if (body.create_payable && (!body.expense_category_id || !body.due_date)) {
      throw new BadRequestException('Categoria de despesa e vencimento são obrigatórios para gerar conta a pagar');
    }
    if (body.create_payable) {
      const pro = await this.prisma.tenantSubscription.findFirst({
        where: {
          tenantId: req.tenantId,
          plan: 'pro',
          status: { in: ['trialing', 'active'] },
          OR: [{ ends_at: null }, { ends_at: { gt: new Date() } }],
        },
      });
      if (!pro) {
        throw new ForbiddenException({
          code: 'FEATURE_REQUIRES_PRO',
          message: 'Gerar conta a pagar pela compra requer o plano Pro',
          feature: 'finance.accounts_payable',
        });
      }
    }
    if (body.expense_category_id) {
      const category = await this.prisma.expenseCategory.findFirst({ where: { id: body.expense_category_id, tenantId: req.tenantId, active: true } });
      if (!category) throw new BadRequestException('Categoria de despesa inválida');
    }

    const lines = body.items.map((item) => ({
      ...item,
      total_cents: Math.round(item.quantity * item.unit_cost_cents),
    }));
    const totalCents = lines.reduce((sum, item) => sum + item.total_cents, 0);

    const key = getIdempotencyKey(req.headers ?? {});
    const result = await executeIdempotent(
      this.prisma,
      req.tenantId,
      key,
      'POST /v1/purchases',
      body,
      req.user?.sub,
      async (tx) => {
        const purchase = await tx.purchase.create({
          data: {
            tenantId: req.tenantId,
            supplierId: body.supplier_id,
            document_no: body.document_no,
            status: 'confirmed',
            purchased_at: parseDate(body.purchased_at, 'purchased_at'),
            total_cents: totalCents,
            notes: body.notes,
            created_by: req.user?.sub,
            confirmed_at: new Date(),
            items: {
              create: lines.map((item) => ({
                productId: item.product_id,
                quantity: new Prisma.Decimal(item.quantity),
                unit_cost_cents: item.unit_cost_cents,
                total_cents: item.total_cents,
              })),
            },
          },
        });

        for (const line of lines) {
          const product = products.find((candidate) => candidate.id === line.product_id)!;
          await tx.product.update({
            where: { id: line.product_id },
            data: {
              cost_cents: line.unit_cost_cents,
              ...(product.stock_controlled ? { stock_quantity: { increment: new Prisma.Decimal(line.quantity) } } : {}),
            },
          });
          if (product.stock_controlled) {
            await tx.stockMovement.create({
              data: {
                tenantId: req.tenantId,
                productId: line.product_id,
                type: 'purchase',
                quantity: new Prisma.Decimal(line.quantity),
                unit_cost_cents: line.unit_cost_cents,
                reference_type: 'purchase',
                reference_id: purchase.id,
                created_by: req.user?.sub,
              },
            });
          }
        }

        if (body.create_payable) {
          const expense = await tx.payableExpense.create({
            data: {
              tenantId: req.tenantId,
              supplierId: body.supplier_id,
              categoryId: body.expense_category_id!,
              description: `Compra ${body.document_no ?? purchase.id}`,
              amount_cents: totalCents,
              due_date: parseDate(body.due_date!, 'due_date'),
              competence_date: monthStart(parseDate(body.purchased_at, 'purchased_at')),
              created_by: req.user?.sub,
            },
          });
          await tx.purchase.update({ where: { id: purchase.id }, data: { payableExpenseId: expense.id } });
        }

        return tx.purchase.findUniqueOrThrow({
          where: { id: purchase.id },
          include: { supplier: true, items: { include: { product: true } }, payableExpense: true },
        });
      },
    );
    return result.value;
  }
}
