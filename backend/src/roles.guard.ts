import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { OperationalRole, ROLES_KEY } from './roles.decorator';

interface RequestWithRole {
  role?: string;
}

const ROLE_ALIASES: Record<string, OperationalRole> = {
  owner: 'manager',
  admin: 'manager',
};

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const allowed = this.reflector.getAllAndOverride<OperationalRole[]>(ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!allowed?.length) return true;

    const request = context.switchToHttp().getRequest<RequestWithRole>();
    const rawRole = request.role;
    const normalizedRole = rawRole ? ROLE_ALIASES[rawRole] ?? rawRole : undefined;
    if (!normalizedRole || !allowed.includes(normalizedRole as OperationalRole)) {
      throw new ForbiddenException('Perfil sem permissão para esta operação');
    }
    return true;
  }
}
