import {
  CanActivate,
  ExecutionContext,
  Injectable,
  ForbiddenException,
  UnauthorizedException,
} from '@nestjs/common';
import { USER_TENANTS } from './db';

@Injectable()
export class TenantGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest();
    const tenantId = request.headers['x-tenant-id'];
    
    if (!tenantId) {
      throw new ForbiddenException('X-Tenant-Id não fornecido');
    }

    if (!request.user) {
      throw new UnauthorizedException('Usuário não autenticado');
    }

    const hasAccess = USER_TENANTS.some(
      (ut) => ut.userId === request.user.sub && ut.tenantId === tenantId,
    );

    if (!hasAccess) {
      throw new ForbiddenException('Usuário não pertence a este tenant');
    }

    request.tenantId = tenantId;
    return true;
  }
}
