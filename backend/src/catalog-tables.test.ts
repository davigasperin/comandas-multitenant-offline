import * as assert from 'node:assert';
import { CatalogController } from './catalog.controller';
import { OrdersController } from './orders.controller';
import { OrdersGateway } from './orders.gateway';
import { PrismaService } from './prisma.service';

async function runCatalogTablesTest() {
  console.log('Executando suíte de testes de catálogo e mesas...');
  const prisma = new PrismaService();
  await prisma.$connect();

  const runId = `${Date.now()}_${process.pid}`;
  const tenant1 = `ten_cat1_${runId}`;
  const tenant2 = `ten_cat2_${runId}`;

  await prisma.tenant.createMany({
    data: [
      { id: tenant1, name: 'Tenant 1', role: 'manager' },
      { id: tenant2, name: 'Tenant 2', role: 'manager' },
    ],
  });

  const catalogController = new CatalogController(prisma);
  const fakeGateway: Partial<OrdersGateway> = { emitToTenant: () => {} };
  const ordersController = new OrdersController(prisma, fakeGateway as OrdersGateway);

  const reqManager1 = { tenantId: tenant1, user: { sub: 'usr_mgr_1' }, headers: {} } as any;
  const reqManager2 = { tenantId: tenant2, user: { sub: 'usr_mgr_2' }, headers: {} } as any;

  // 1. Criação de categoria e isolamento multi-tenant
  const cat1 = await catalogController.createCategory(reqManager1, {
    name: 'Bebidas Quentes',
    production_area: 'bar',
  });
  assert.strictEqual(cat1.name, 'Bebidas Quentes');
  assert.strictEqual(cat1.production_area, 'bar');

  const listCatT2 = await catalogController.listCategories(reqManager2);
  assert.strictEqual(listCatT2.data.length, 0, 'Tenant 2 não deve enxergar categorias do Tenant 1');

  // 2. Criação de produtos (centavos exatos, ativo, disponível)
  const prod1 = await catalogController.createProduct(reqManager1, {
    name: 'Café Espresso',
    price_cents: 850,
    category_id: cat1.id,
    active: true,
    available: true,
  });
  assert.strictEqual(prod1.price_cents, 850);
  assert.strictEqual(prod1.available, true);

  const prodInactive = await catalogController.createProduct(reqManager1, {
    name: 'Item Esgotado',
    price_cents: 1200,
    available: false,
  });

  // 3. Bloqueio ao adicionar item inativo ou indisponível
  const orderReq = {
    tenantId: tenant1,
    user: { sub: 'usr_waiter_1' },
    headers: { 'x-idempotency-key': `key_order_${runId}` },
  } as any;
  const order = await ordersController.createOrder(orderReq, { table_label: 'Comanda Balcão' });

  let unavailableBlocked = false;
  try {
    await ordersController.addItem(
      { tenantId: tenant1, user: { sub: 'usr_waiter_1' }, headers: { 'x-idempotency-key': `k_item_unavail_${runId}` } } as any,
      order.id,
      { product_id: prodInactive.id, quantity: 1 },
    );
  } catch (err: any) {
    unavailableBlocked = true;
  }
  assert.strictEqual(unavailableBlocked, true, 'Item indisponível deve ser rejeitado ao adicionar');

  // Adiciona item válido com preço canônico do servidor
  const orderWithItem = await ordersController.addItem(
    { tenantId: tenant1, user: { sub: 'usr_waiter_1' }, headers: { 'x-idempotency-key': `k_item_avail_${runId}` } } as any,
    order.id,
    { product_id: prod1.id, quantity: 2, unit_price_cents: 100 }, // Preço fraudulento no payload
  );
  assert.strictEqual(orderWithItem.items[0].unit_price_cents, 850, 'Deve usar o preço canônico do produto no banco');

  // 4. Criação de mesas e unicidade de rótulo
  const tableA = await catalogController.createTable(reqManager1, {
    label: 'Mesa 10',
    capacity: 4,
    pos_x: 50,
    pos_y: 100,
    width: 120,
    height: 120,
    shape: 'square',
  });
  assert.strictEqual(tableA.label, 'Mesa 10');

  let duplicateLabelBlocked = false;
  try {
    await catalogController.createTable(reqManager1, { label: 'Mesa 10' });
  } catch (err: any) {
    duplicateLabelBlocked = true;
  }
  assert.strictEqual(duplicateLabelBlocked, true, 'Não deve permitir mesa com mesmo rótulo no tenant');

  // 5. Ocupação da mesa ao abrir comanda e unicidade parcial (uma comanda aberta por mesa)
  const orderTable1 = await ordersController.createOrder(
    { tenantId: tenant1, user: { sub: 'usr_waiter_1' }, headers: { 'x-idempotency-key': `k_ord_t1_${runId}` } } as any,
    { table_label: 'Mesa 10', table_id: tableA.id },
  );
  assert.strictEqual(orderTable1.tableId, tableA.id);

  let secondOrderBlocked = false;
  try {
    await ordersController.createOrder(
      { tenantId: tenant1, user: { sub: 'usr_waiter_2' }, headers: { 'x-idempotency-key': `k_ord_t2_${runId}` } } as any,
      { table_label: 'Mesa 10', table_id: tableA.id },
    );
  } catch (err: any) {
    secondOrderBlocked = true;
  }
  assert.strictEqual(secondOrderBlocked, true, 'Segunda comanda aberta na mesma mesa deve ser bloqueada por conflito');

  // 6. Transferência atômica de mesa
  const tableB = await catalogController.createTable(reqManager1, {
    label: 'Mesa 20',
    capacity: 6,
  });

  const transferred = await ordersController.transferTable(
    { tenantId: tenant1, user: { sub: 'usr_waiter_1' }, headers: {} } as any,
    orderTable1.id,
    { target_table_id: tableB.id },
  );
  assert.strictEqual(transferred.tableId, tableB.id);
  assert.strictEqual(transferred.table_label, 'Mesa 20');

  // Agora a Mesa 10 está livre e pode receber nova comanda
  const orderNewTable10 = await ordersController.createOrder(
    { tenantId: tenant1, user: { sub: 'usr_waiter_1' }, headers: { 'x-idempotency-key': `k_ord_t10_new_${runId}` } } as any,
    { table_label: 'Mesa 10', table_id: tableA.id },
  );
  assert.strictEqual(orderNewTable10.tableId, tableA.id);

  // 7. Liquidação da comanda libera a mesa
  // Adiciona item para total > 0
  await ordersController.addItem(
    { tenantId: tenant1, user: { sub: 'usr_waiter_1' }, headers: { 'x-idempotency-key': `k_item_t10_${runId}` } } as any,
    orderNewTable10.id,
    { product_id: prod1.id, quantity: 1 },
  );

  await ordersController.settleOrder(
    { tenantId: tenant1, user: { sub: 'usr_cashier' }, headers: { 'x-idempotency-key': `k_settle_t10_${runId}` } } as any,
    orderNewTable10.id,
    {
      expected_version: 2,
      payments: [{ method: 'cash', amount_cents: 850 }],
      discount_cents: 0,
      service_fee_bps: 0,
    },
  );

  const tablesStatus = await catalogController.listTables(reqManager1);
  const finalTableA = tablesStatus.data.find((t) => t.id === tableA.id);
  assert.strictEqual(finalTableA?.is_occupied, false, 'Mesa A deve estar desocupada após liquidação');

  await prisma.$disconnect();
  console.log('Todos os testes de catálogo, produtos, mesas, ocupação e transferência passaram com sucesso!');
}

runCatalogTablesTest().catch((e) => {
  console.error('Catalog and tables test failed:', e);
  process.exit(1);
});
