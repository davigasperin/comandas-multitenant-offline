import { SetMetadata } from '@nestjs/common';

export const ROLES_KEY = 'roles';
export type OperationalRole = 'waiter' | 'kitchen' | 'cashier' | 'manager';
export const Roles = (...roles: OperationalRole[]) => SetMetadata(ROLES_KEY, roles);
