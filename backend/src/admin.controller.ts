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
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from './auth.guard';
import { hashPassword } from './auth.utils';
import { CreateEmployeeDto, UpdateDiscountPolicyDto, UpdateEmployeeDto, UpdatePrinterSettingDto } from './dto/management.dto';
import { OrdersGateway } from './orders.gateway';
import { PrismaService } from './prisma.service';
import { Roles } from './roles.decorator';
import { RolesGuard } from './roles.guard';
import { TenantGuard } from './tenant.guard';

interface RequestContext {
  tenantId: string;
  user?: { sub: string };
}

@UseGuards(AuthGuard, TenantGuard, RolesGuard)
@Roles('manager')
@Controller('v1/employees')
export class EmployeesController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly ordersGateway: OrdersGateway,
  ) {}

  @Get()
  async list(@Request() req: RequestContext) {
    const memberships = await this.prisma.userTenant.findMany({
      where: { tenantId: req.tenantId },
      include: { user: { select: { id: true, name: true, email: true, createdAt: true } } },
      orderBy: { user: { name: 'asc' } },
    });
    return {
      data: memberships.map(({ user, role, active }) => ({ ...user, role, active })),
    };
  }

  @Post()
  async create(@Request() req: RequestContext, @Body() body: CreateEmployeeDto) {
    const email = body.email.trim().toLowerCase();
    const existingUser = await this.prisma.user.findUnique({ where: { email } });
    if (existingUser) {
      const existingMembership = await this.prisma.userTenant.findUnique({
        where: { userId_tenantId: { userId: existingUser.id, tenantId: req.tenantId } },
      });
      if (existingMembership) throw new ConflictException('Funcionário já pertence a este estabelecimento');
      const membership = await this.prisma.userTenant.create({
        data: { userId: existingUser.id, tenantId: req.tenantId, role: body.role, active: true },
        include: { user: { select: { id: true, name: true, email: true, createdAt: true } } },
      });
      return { ...membership.user, role: membership.role, active: membership.active, existing_account: true };
    }

    const user = await this.prisma.user.create({
      data: {
        name: body.name.trim(),
        email,
        password: await hashPassword(body.password),
        tenants: { create: { tenantId: req.tenantId, role: body.role, active: true } },
      },
      select: { id: true, name: true, email: true, createdAt: true },
    });
    return { ...user, role: body.role, active: true, existing_account: false };
  }

  @Patch(':userId')
  async update(@Request() req: RequestContext, @Param('userId') userId: string, @Body() body: UpdateEmployeeDto) {
    const membership = await this.prisma.userTenant.findUnique({
      where: { userId_tenantId: { userId, tenantId: req.tenantId } },
    });
    if (!membership) throw new NotFoundException('Funcionário não encontrado');
    if (userId === req.user?.sub && body.active === false) {
      throw new BadRequestException('Você não pode desativar o próprio acesso');
    }

    await this.prisma.$transaction(async (tx) => {
      if (body.name) {
        await tx.user.update({
          where: { id: userId },
          data: { name: body.name.trim() },
        });
      }
      if (body.role || body.active !== undefined) {
        await tx.userTenant.update({
          where: { userId_tenantId: { userId, tenantId: req.tenantId } },
          data: { role: body.role, active: body.active },
        });
      }
    });
    const updated = await this.prisma.userTenant.findUniqueOrThrow({
      where: { userId_tenantId: { userId, tenantId: req.tenantId } },
      include: { user: { select: { id: true, name: true, email: true, createdAt: true } } },
    });
    if (body.active === false) {
      await this.ordersGateway.disconnectUserFromTenant(userId, req.tenantId);
    }
    return { ...updated.user, role: updated.role, active: updated.active };
  }

  @Delete(':userId')
  async deactivate(@Request() req: RequestContext, @Param('userId') userId: string) {
    if (userId === req.user?.sub) throw new BadRequestException('Você não pode desativar o próprio acesso');
    const result = await this.prisma.userTenant.updateMany({
      where: { userId, tenantId: req.tenantId },
      data: { active: false },
    });
    if (!result.count) throw new NotFoundException('Funcionário não encontrado');
    await this.ordersGateway.disconnectUserFromTenant(userId, req.tenantId);
    return { ok: true };
  }
}

@UseGuards(AuthGuard, TenantGuard, RolesGuard)
@Controller('v1/settings')
export class SettingsController {
  constructor(private readonly prisma: PrismaService) {}

  @Get('entitlements')
  async entitlements(@Request() req: RequestContext) {
    const now = new Date();
    const subscription = await this.prisma.tenantSubscription.findFirst({
      where: {
        tenantId: req.tenantId,
        status: { in: ['trialing', 'active'] },
        OR: [{ ends_at: null }, { ends_at: { gt: now } }],
      },
      orderBy: { starts_at: 'desc' },
    });
    const plan = subscription?.plan ?? 'free';
    return {
      plan,
      subscription_status: subscription?.status ?? 'inactive',
      features: {
        accounts_payable: plan === 'pro',
        profit_margin: plan === 'pro',
        dynamic_pix: plan === 'pro',
      },
    };
  }

  @Get('printer')
  async printer(@Request() req: RequestContext) {
    return this.prisma.printerSetting.upsert({
      where: { tenantId: req.tenantId },
      create: { tenantId: req.tenantId },
      update: {},
    });
  }

  @Roles('manager')
  @Patch('printer')
  async updatePrinter(@Request() req: RequestContext, @Body() body: UpdatePrinterSettingDto) {
    return this.prisma.printerSetting.upsert({
      where: { tenantId: req.tenantId },
      create: { tenantId: req.tenantId, ...body },
      update: body,
    });
  }

  @Get('discount-policy')
  async discountPolicy(@Request() req: RequestContext) {
    return this.prisma.tenant.findUniqueOrThrow({
      where: { id: req.tenantId },
      select: { cashier_discount_limit_bps: true },
    });
  }

  @Roles('manager')
  @Patch('discount-policy')
  async updateDiscountPolicy(@Request() req: RequestContext, @Body() body: UpdateDiscountPolicyDto) {
    return this.prisma.tenant.update({
      where: { id: req.tenantId },
      data: { cashier_discount_limit_bps: body.cashier_discount_limit_bps },
      select: { cashier_discount_limit_bps: true },
    });
  }

  @Roles('manager')
  @Get('audit-log')
  async audit(@Request() req: RequestContext) {
    return {
      data: await this.prisma.auditLog.findMany({
        where: { tenantId: req.tenantId },
        include: { user: { select: { id: true, name: true, email: true } } },
        orderBy: { createdAt: 'desc' },
        take: 500,
      }),
    };
  }
}
