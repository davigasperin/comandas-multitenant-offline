import {
  BadRequestException,
  Body,
  ConflictException,
  Controller,
  Delete,
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
import {
  CreateCategoryDto,
  CreateProductDto,
  CreateTableDto,
  UpdateCategoryDto,
  UpdateProductDto,
  UpdateTableDto,
  UpdateTableLayoutDto,
} from './dto/orders.dto';
import { PrismaService } from './prisma.service';
import { TenantGuard } from './tenant.guard';
import { Roles } from './roles.decorator';
import { RolesGuard } from './roles.guard';
import { pageArgs, pageResult } from './pagination';

interface RequestContext {
  tenantId: string;
  user?: { sub: string };
  headers: Record<string, string | string[] | undefined>;
}

@UseGuards(AuthGuard, TenantGuard, RolesGuard)
@Controller('v1')
export class CatalogController {
  constructor(private readonly prisma: PrismaService) {}

  // ---------------- CATEGORIES ----------------

  @Get('categories')
  async listCategories(@Request() req: RequestContext, @Query('all') all?: string) {
    const showAll = all === 'true' || all === '1';
    const categories = await this.prisma.category.findMany({
      where: {
        tenantId: req.tenantId,
        ...(showAll ? {} : { active: true }),
      },
      orderBy: [{ sort_order: 'asc' }, { name: 'asc' }],
    });
    return { data: categories };
  }

  @Roles('manager')
  @Post('categories')
  async createCategory(@Request() req: RequestContext, @Body() body: CreateCategoryDto) {
    const category = await this.prisma.category.create({
      data: {
        tenantId: req.tenantId,
        name: body.name.trim(),
        sort_order: body.sort_order ?? 0,
        active: body.active ?? true,
        production_area: body.production_area ?? 'kitchen',
      },
    });
    return category;
  }

  @Roles('manager')
  @Patch('categories/:id')
  async updateCategory(
    @Request() req: RequestContext,
    @Param('id') id: string,
    @Body() body: UpdateCategoryDto,
  ) {
    const existing = await this.prisma.category.findFirst({
      where: { id, tenantId: req.tenantId },
    });
    if (!existing) throw new NotFoundException('Categoria não encontrada');

    return this.prisma.category.update({
      where: { id },
      data: {
        ...(body.name !== undefined ? { name: body.name.trim() } : {}),
        ...(body.sort_order !== undefined ? { sort_order: body.sort_order } : {}),
        ...(body.active !== undefined ? { active: body.active } : {}),
        ...(body.production_area !== undefined ? { production_area: body.production_area } : {}),
      },
    });
  }

  @Roles('manager')
  @Delete('categories/:id')
  async deleteCategory(@Request() req: RequestContext, @Param('id') id: string) {
    const existing = await this.prisma.category.findFirst({
      where: { id, tenantId: req.tenantId },
    });
    if (!existing) throw new NotFoundException('Categoria não encontrada');

    return this.prisma.category.update({
      where: { id },
      data: { active: false },
    });
  }

  // ---------------- PRODUCTS ----------------

  @Get('products')
  async listProducts(
    @Request() req: RequestContext,
    @Query('all') all?: string,
    @Query('categoryId') categoryId?: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    const showAll = all === 'true' || all === '1';
    const products = await this.prisma.product.findMany({
      where: {
        tenantId: req.tenantId,
        ...(showAll ? {} : { active: true, available: true }),
        ...(categoryId ? { categoryId } : {}),
      },
      include: { category: true },
      orderBy: [{ sort_order: 'asc' }, { name: 'asc' }, { id: 'asc' }],
      ...pageArgs(limit, cursor),
    });
    return pageResult(products, limit);
  }

  @Roles('manager')
  @Post('products')
  async createProduct(@Request() req: RequestContext, @Body() body: CreateProductDto) {
    if (body.category_id) {
      const category = await this.prisma.category.findFirst({
        where: { id: body.category_id, tenantId: req.tenantId },
      });
      if (!category) throw new NotFoundException('Categoria associada não encontrada');
    }

    return this.prisma.product.create({
      data: {
        tenantId: req.tenantId,
        name: body.name.trim(),
        price_cents: body.price_cents,
        cost_cents: body.cost_cents ?? 0,
        sku: body.sku?.trim() || null,
        unit: body.unit ?? 'unit',
        stock_controlled: body.stock_controlled ?? false,
        minimum_stock: body.minimum_stock ?? 0,
        categoryId: body.category_id ?? null,
        active: body.active ?? true,
        available: body.available ?? true,
        sort_order: body.sort_order ?? 0,
      },
      include: { category: true },
    });
  }

  @Roles('manager')
  @Patch('products/:id')
  async updateProduct(
    @Request() req: RequestContext,
    @Param('id') id: string,
    @Body() body: UpdateProductDto,
  ) {
    const existing = await this.prisma.product.findFirst({
      where: { id, tenantId: req.tenantId },
    });
    if (!existing) throw new NotFoundException('Produto não encontrado');

    if (body.category_id !== undefined && body.category_id !== null) {
      const category = await this.prisma.category.findFirst({
        where: { id: body.category_id, tenantId: req.tenantId },
      });
      if (!category) throw new NotFoundException('Categoria associada não encontrada');
    }

    return this.prisma.product.update({
      where: { id },
      data: {
        ...(body.name !== undefined ? { name: body.name.trim() } : {}),
        ...(body.price_cents !== undefined ? { price_cents: body.price_cents } : {}),
        ...(body.cost_cents !== undefined ? { cost_cents: body.cost_cents } : {}),
        ...(body.sku !== undefined ? { sku: body.sku.trim() || null } : {}),
        ...(body.unit !== undefined ? { unit: body.unit } : {}),
        ...(body.stock_controlled !== undefined ? { stock_controlled: body.stock_controlled } : {}),
        ...(body.minimum_stock !== undefined ? { minimum_stock: body.minimum_stock } : {}),
        ...(body.category_id !== undefined ? { categoryId: body.category_id } : {}),
        ...(body.active !== undefined ? { active: body.active } : {}),
        ...(body.available !== undefined ? { available: body.available } : {}),
        ...(body.sort_order !== undefined ? { sort_order: body.sort_order } : {}),
      },
      include: { category: true },
    });
  }

  @Roles('manager')
  @Delete('products/:id')
  async deleteProduct(@Request() req: RequestContext, @Param('id') id: string) {
    const existing = await this.prisma.product.findFirst({
      where: { id, tenantId: req.tenantId },
    });
    if (!existing) throw new NotFoundException('Produto não encontrado');

    return this.prisma.product.update({
      where: { id },
      data: { active: false },
    });
  }

  // ---------------- TABLES ----------------

  @Get('tables')
  async listTables(@Request() req: RequestContext, @Query('all') all?: string) {
    const showAll = all === 'true' || all === '1';
    const tables = await this.prisma.diningTable.findMany({
      where: {
        tenantId: req.tenantId,
        ...(showAll ? {} : { active: true }),
      },
      include: {
        orders: {
          where: {
            tenantId: req.tenantId,
            status: { notIn: ['closed', 'canceled'] },
          },
          select: {
            id: true,
            status: true,
            table_label: true,
            opened_at: true,
            total_cents: true,
          },
        },
      },
      orderBy: [{ label: 'asc' }],
    });

    const mapped = tables.map((t) => {
      const activeOrder = t.orders[0] ?? null;
      return {
        id: t.id,
        tenantId: t.tenantId,
        label: t.label,
        capacity: t.capacity,
        pos_x: t.position_x,
        pos_y: t.position_y,
        width: t.width,
        height: t.height,
        shape: t.shape,
        active: t.active,
        is_occupied: !!activeOrder,
        active_order: activeOrder,
      };
    });

    return { data: mapped };
  }

  @Roles('manager')
  @Post('tables')
  async createTable(@Request() req: RequestContext, @Body() body: CreateTableDto) {
    const label = body.label.trim();
    const existing = await this.prisma.diningTable.findFirst({
      where: { tenantId: req.tenantId, label, active: true },
    });
    if (existing) {
      throw new ConflictException(`Mesa com o rótulo "${label}" já existe`);
    }

    const created = await this.prisma.diningTable.create({
      data: {
        tenantId: req.tenantId,
        label,
        capacity: body.capacity ?? 4,
        position_x: body.pos_x ?? 0,
        position_y: body.pos_y ?? 0,
        width: body.width ?? 120,
        height: body.height ?? 120,
        shape: body.shape ?? 'square',
      },
    });

    return {
      id: created.id,
      tenantId: created.tenantId,
      label: created.label,
      capacity: created.capacity,
      pos_x: created.position_x,
      pos_y: created.position_y,
      width: created.width,
      height: created.height,
      shape: created.shape,
      active: created.active,
      is_occupied: false,
      active_order: null,
    };
  }

  @Roles('manager')
  @Patch('tables/:id')
  async updateTable(
    @Request() req: RequestContext,
    @Param('id') id: string,
    @Body() body: UpdateTableDto,
  ) {
    const existing = await this.prisma.diningTable.findFirst({
      where: { id, tenantId: req.tenantId },
    });
    if (!existing) throw new NotFoundException('Mesa não encontrada');

    if (body.label !== undefined && body.label.trim() !== existing.label) {
      const duplicate = await this.prisma.diningTable.findFirst({
        where: { tenantId: req.tenantId, label: body.label.trim(), active: true, id: { not: id } },
      });
      if (duplicate) throw new ConflictException(`Mesa "${body.label.trim()}" já existe`);
    }

    const updated = await this.prisma.diningTable.update({
      where: { id },
      data: {
        ...(body.label !== undefined ? { label: body.label.trim() } : {}),
        ...(body.capacity !== undefined ? { capacity: body.capacity } : {}),
        ...(body.pos_x !== undefined ? { position_x: body.pos_x } : {}),
        ...(body.pos_y !== undefined ? { position_y: body.pos_y } : {}),
        ...(body.width !== undefined ? { width: body.width } : {}),
        ...(body.height !== undefined ? { height: body.height } : {}),
        ...(body.shape !== undefined ? { shape: body.shape } : {}),
        ...(body.active !== undefined ? { active: body.active } : {}),
      },
    });

    return updated;
  }

  @Roles('manager')
  @Patch('tables/:id/layout')
  async updateTableLayout(
    @Request() req: RequestContext,
    @Param('id') id: string,
    @Body() body: UpdateTableLayoutDto,
  ) {
    const existing = await this.prisma.diningTable.findFirst({
      where: { id, tenantId: req.tenantId },
    });
    if (!existing) throw new NotFoundException('Mesa não encontrada');

    return this.prisma.diningTable.update({
      where: { id },
      data: {
        position_x: body.pos_x,
        position_y: body.pos_y,
        ...(body.width !== undefined ? { width: body.width } : {}),
        ...(body.height !== undefined ? { height: body.height } : {}),
        ...(body.shape !== undefined ? { shape: body.shape } : {}),
      },
    });
  }

  @Roles('manager')
  @Delete('tables/:id')
  async deleteTable(@Request() req: RequestContext, @Param('id') id: string) {
    const existing = await this.prisma.diningTable.findFirst({
      where: { id, tenantId: req.tenantId },
    });
    if (!existing) throw new NotFoundException('Mesa não encontrada');

    const activeOrder = await this.prisma.order.findFirst({
      where: { tableId: id, tenantId: req.tenantId, status: { notIn: ['closed', 'canceled'] } },
    });
    if (activeOrder) throw new ConflictException('Não é possível desativar mesa ocupada com comanda aberta');

    return this.prisma.diningTable.update({
      where: { id },
      data: { active: false },
    });
  }
}
