import * as assert from 'node:assert';
import { OrdersController } from './orders.controller';
import { OrdersGateway } from './orders.gateway';
import { PrismaService } from './prisma.service';

async function runConcurrencyAndFinancialTests() {
  console.log('Executando suíte de testes de concorrência e integridade financeira...');
  const prisma = new PrismaService();
  await prisma.$connect();

  const runId = `${Date.now()}_${process.pid}`;
  const tenantId = `ten_fin_${runId}`;
  await prisma.tenant.create({
    data: { id: tenantId, name: 'Empresa de teste financeiro', role: 'admin' },
  });

  const product = await prisma.product.create({
    data: {
      tenantId,
      name: 'Item Especial',
      price_cents: 1999, // R$ 19,99
    },
  });
  assert.strictEqual(Number.isInteger(product.price_cents), true, 'Product price_cents must be strict integer');

  const fakeGateway: Partial<OrdersGateway> = {
    emitToTenant: () => {},
  };
  const controller = new OrdersController(prisma, fakeGateway as OrdersGateway);

  const reqUser1 = { tenantId, user: { sub: 'usr_garcom_1' }, headers: {} } as any;
  const reqUser2 = { tenantId, user: { sub: 'usr_cozinha_2' }, headers: {} } as any;

  // 1. Criar comanda
  const order = await controller.createOrder(reqUser1, { table_label: 'Mesa 77' });
  assert.strictEqual(order.version, 1, 'Initial order version must be 1');
  assert.strictEqual(order.status, 'open');

  // Verificar histórico inicial
  const historyInitial = await prisma.orderStatusHistory.findMany({ where: { orderId: order.id } });
  assert.strictEqual(historyInitial.length, 1);
  assert.strictEqual(historyInitial[0].to_status, 'open');
  assert.strictEqual(historyInitial[0].changed_by, 'usr_garcom_1');

  // 2. Adicionar item com preço exato em centavos
  const withItem = await controller.addItem(reqUser1, order.id, {
    product_id: product.id,
    quantity: 3,
  });
  assert.strictEqual(withItem.items[0].unit_price_cents, 1999, 'Item unit_price_cents must preserve exact integer cents');
  assert.strictEqual(withItem.items[0].unit_price_cents * withItem.items[0].quantity, 5997);
  assert.strictEqual(withItem.version, 2, 'Adding items must increment version for optimistic locking');

  // 3. Teste de conflito de concorrência otimista
  // O cliente A lê a versão 2; o cliente B também lê a versão 2
  // O cliente A atualiza para sentToKitchen com expected_version: 2 e obtém sucesso
  const updatedA = await controller.updateOrderStatus(reqUser1, order.id, {
    status: 'sentToKitchen',
    expected_version: 2,
  });
  assert.strictEqual(updatedA.status, 'sentToKitchen');
  assert.strictEqual(updatedA.version, 3);

  // O cliente B tenta atualizar com expected_version: 2 desatualizada e deve receber conflito 409
  let conflictCaught = false;
  try {
    await controller.updateOrderStatus(reqUser2, order.id, {
      status: 'delivered',
      expected_version: 2, // versão desatualizada
    });
  } catch (err: any) {
    if (err?.status === 409 || err?.response?.statusCode === 409) {
      conflictCaught = true;
    }
  }
  assert.strictEqual(conflictCaught, true, 'Stale expected_version must trigger ConflictException (409)');

  // 4. Atualizar para delivered com a versão atual 3
  const updatedB = await controller.updateOrderStatus(reqUser2, order.id, {
    status: 'delivered',
    expected_version: 3,
  });
  assert.strictEqual(updatedB.status, 'delivered');
  assert.strictEqual(updatedB.version, 4);

  // 5. Validar registro de auditoria
  const historyFull = await prisma.orderStatusHistory.findMany({
    where: { orderId: order.id },
    orderBy: { changed_at: 'asc' },
  });
  assert.strictEqual(historyFull.length, 3, 'Must record open, sentToKitchen, and delivered in audit log');
  assert.strictEqual(historyFull[1].from_status, 'open');
  assert.strictEqual(historyFull[1].to_status, 'sentToKitchen');
  assert.strictEqual(historyFull[1].changed_by, 'usr_garcom_1');
  assert.strictEqual(historyFull[2].from_status, 'sentToKitchen');
  assert.strictEqual(historyFull[2].to_status, 'delivered');
  assert.strictEqual(historyFull[2].changed_by, 'usr_cozinha_2');

  await prisma.$disconnect();
  console.log('Suíte de Concorrência e Integridade Financeira executada com sucesso!');
}

runConcurrencyAndFinancialTests().catch((e) => {
  console.error('Falha nos testes de concorrência e integridade financeira:', e);
  process.exit(1);
});
