import { CanActivate, ExecutionContext, ForbiddenException, Injectable, UnauthorizedException } from '@nestjs/common';
import { PrismaService } from './prisma.service';

interface RequestWithAuth {
  user?: { sub: string };
  headers: Record<string, string | string[] | undefined>;
  tenantId?: string;
  role?: string;
}

@Injectable()
export class TenantGuard implements CanActivate {
  constructor(private readonly prisma: PrismaService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<RequestWithAuth>();
    const tenantId = request.headers['x-tenant-id'];
    const normalizedTenantId = Array.isArray(tenantId) ? tenantId[0] : tenantId;
    if (!normalizedTenantId) throw new ForbiddenException('X-Tenant-Id não fornecido');
    if (!request.user) throw new UnauthorizedException('Usuário não autenticado');
    const access = await this.prisma.userTenant.findUnique({
      where: { userId_tenantId: { userId: request.user.sub, tenantId: normalizedTenantId } },
    });
    if (!access || !access.active) throw new ForbiddenException('Usuário não pertence a este tenant ou está inativo');
    request.tenantId = normalizedTenantId;
    request.role = access.role;
    return true;
  }
}
