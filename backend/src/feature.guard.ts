import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { FEATURE_KEY } from './feature.decorator';
import { PrismaService } from './prisma.service';

interface FeatureRequest {
  tenantId?: string;
}

const PRO_FEATURES = new Set([
  'finance.accounts_payable',
  'reports.profit_margin',
  'pix.dynamic_charge',
]);

@Injectable()
export class FeatureGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly prisma: PrismaService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const feature = this.reflector.getAllAndOverride<string>(FEATURE_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!feature || !PRO_FEATURES.has(feature)) return true;

    const request = context.switchToHttp().getRequest<FeatureRequest>();
    if (!request.tenantId) throw new ForbiddenException('Tenant não selecionado');

    const now = new Date();
    const subscription = await this.prisma.tenantSubscription.findFirst({
      where: {
        tenantId: request.tenantId,
        plan: 'pro',
        status: { in: ['trialing', 'active'] },
        OR: [{ ends_at: null }, { ends_at: { gt: now } }],
      },
      orderBy: { starts_at: 'desc' },
    });
    if (!subscription) {
      throw new ForbiddenException({
        code: 'FEATURE_REQUIRES_PRO',
        message: 'Este recurso requer o plano Pro',
        feature,
      });
    }
    return true;
  }
}
