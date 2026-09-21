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
    data: { id: tenantId, name: 'Financial Test Tenant', role: 'admin' },
  });

  const product = await prisma.product.create({
    data: {
      tenantId,
      name: 'Item Especial',
      price_cents: 1999,
    },
  });
  assert.strictEqual(Number.isInteger(product.price_cents), true, 'Product price_cents must be strict integer');

  const fakeGateway: Partial<OrdersGateway> = {
    emitToTenant: () => {},
  };
  const controller = new OrdersController(prisma, fakeGateway as OrdersGateway);

  const reqUser1 = { tenantId, user: { sub: 'usr_garcom_1' }, headers: { 'x-idempotency-key': `k1_${runId}` } } as any;
  const reqUser2 = { tenantId, user: { sub: 'usr_cozinha_2' }, headers: { 'x-idempotency-key': `k2_${runId}` } } as any;

  // 1. Criar pedido
  const order = await controller.createOrder(reqUser1, { table_label: 'Mesa 77' });
  assert.strictEqual(order.version, 1, 'Versão inicial deve ser 1');
  assert.strictEqual(order.status, 'open');

  // 2. Adicionar item usando centavos exatos e versão esperada
  const withItem = await controller.addItem(
    { tenantId, user: { sub: 'usr_garcom_1' }, headers: { 'x-idempotency-key': `k_item_${runId}` } } as any,
    order.id,
    {
      product_id: product.id,
      quantity: 3,
      expected_version: 1,
    },
  );
  assert.strictEqual(withItem.items[0].unit_price_cents, 1999);
  assert.strictEqual(withItem.version, 2);

  // 3. Conflito ao adicionar item com versão desatualizada
  let itemVersionConflict = false;
  try {
    await controller.addItem(
      { tenantId, user: { sub: 'usr_garcom_1' }, headers: { 'x-idempotency-key': `k_stale_${runId}` } } as any,
      order.id,
      {
        product_id: product.id,
        quantity: 1,
        expected_version: 1, // desatualizado
      },
    );
  } catch (err: any) {
    if (err?.status === 409 || err?.response?.statusCode === 409) {
      itemVersionConflict = true;
    }
  }
  assert.strictEqual(itemVersionConflict, true, 'Adição de item com expected_version desatualizado deve lançar 409');

  // 4. Transição de status
  const updatedA = await controller.updateOrderStatus(
    { tenantId, user: { sub: 'usr_garcom_1' }, headers: { 'x-idempotency-key': `k_stat1_${runId}` } } as any,
    order.id,
    {
      status: 'sentToKitchen',
      expected_version: 2,
    },
  );
  assert.strictEqual(updatedA.status, 'sentToKitchen');
  assert.strictEqual(updatedA.version, 3);

  // 5. Fechamento da comanda com versionamento
  const closed = await controller.closeOrder(
    { tenantId, user: { sub: 'usr_caixa_3' }, headers: { 'x-idempotency-key': `k_close_${runId}` } } as any,
    order.id,
    { expected_version: 3 },
  );
  assert.strictEqual(closed.status, 'closed');
  assert.strictEqual(closed.version, 4);

  // 6. Tentativa de adicionar item em comanda fechada deve ser rejeitada imediatamente
  let itemOnClosedRejected = false;
  try {
    await controller.addItem(
      { tenantId, user: { sub: 'usr_garcom_1' }, headers: { 'x-idempotency-key': `k_late_${runId}` } } as any,
      order.id,
      { product_id: product.id, quantity: 1 },
    );
  } catch (err: any) {
    itemOnClosedRejected = true;
  }
  assert.strictEqual(itemOnClosedRejected, true, 'Adicionar item em comanda fechada deve ser bloqueado');

  await prisma.$disconnect();
  console.log('Suíte de Concorrência e Integridade Financeira executada com sucesso!');
}

runConcurrencyAndFinancialTests().catch((e) => {
  console.error('Concurrency/Financial tests failed:', e);
  process.exit(1);
});
