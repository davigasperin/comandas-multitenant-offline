import * as assert from 'node:assert';
import { Reflector } from '@nestjs/core';
import { RolesGuard } from './roles.guard';
import { ExecutionContext } from '@nestjs/common';

function createMockContext(role: string | undefined, handlerRoles: string[] | undefined): ExecutionContext {
  const reflector = new Reflector();
  const mockHandler = () => {};
  if (handlerRoles) {
    Reflect.defineMetadata('roles', handlerRoles, mockHandler);
  }

  return {
    getHandler: () => mockHandler,
    getClass: () => class {},
    switchToHttp: () => ({
      getRequest: () => ({ role }),
    }),
  } as unknown as ExecutionContext;
}

function testRbacMatrix() {
  console.log('Iniciando validação da matriz RBAC...');
  const guard = new RolesGuard(new Reflector());

  // 1. Garçom cria comanda e adiciona item, mas não fecha nem avança status da cozinha
  const waiterContextCreate = createMockContext('waiter', ['waiter', 'cashier', 'manager']);
  assert.strictEqual(guard.canActivate(waiterContextCreate), true);

  const waiterContextClose = createMockContext('waiter', ['cashier', 'manager']);
  assert.throws(() => guard.canActivate(waiterContextClose), /Perfil sem permissão/);

  // 2. Cozinha altera status, mas não abre comanda nem fecha conta
  const kitchenContextStatus = createMockContext('kitchen', ['kitchen', 'cashier', 'manager']);
  assert.strictEqual(guard.canActivate(kitchenContextStatus), true);

  const kitchenContextCreate = createMockContext('kitchen', ['waiter', 'cashier', 'manager']);
  assert.throws(() => guard.canActivate(kitchenContextCreate), /Perfil sem permissão/);

  // 3. Caixa pode abrir comanda, adicionar itens, alterar status e fechar
  const cashierContextClose = createMockContext('cashier', ['cashier', 'manager']);
  assert.strictEqual(guard.canActivate(cashierContextClose), true);

  const cashierContextCreate = createMockContext('cashier', ['waiter', 'cashier', 'manager']);
  assert.strictEqual(guard.canActivate(cashierContextCreate), true);

  // 4. Gerente (manager / admin / owner) tem acesso a tudo
  const managerContext = createMockContext('manager', ['cashier', 'manager']);
  assert.strictEqual(guard.canActivate(managerContext), true);

  const adminContext = createMockContext('admin', ['cashier', 'manager']);
  assert.strictEqual(guard.canActivate(adminContext), true);

  console.log('Validação da matriz RBAC concluída com sucesso!');
}

testRbacMatrix();
