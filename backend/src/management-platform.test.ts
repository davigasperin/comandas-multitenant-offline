import * as assert from 'node:assert';
import { createHmac } from 'node:crypto';
import { FinanceController, InventoryController, PurchasesController, SuppliersController } from './management.controller';
import { ReportsController } from './reports.controller';
import { PrismaService } from './prisma.service';
import { OrdersController } from './orders.controller';
import { OrdersGateway } from './orders.gateway';
import { PixWebhookController } from './pix.controller';

async function runManagementPlatformTests() {
  console.log('Executando suíte de gestão, estoque, financeiro e relatórios...');
  const prisma = new PrismaService();
  await prisma.$connect();

  const runId = `${Date.now()}_${process.pid}`;
  const tenantId = `ten_management_${runId}`;
  const userId = `usr_management_${runId}`;
  await prisma.user.create({
    data: { id: userId, name: 'Gestor Teste', email: `${userId}@test.local`, password: 'hash' },
  });
  await prisma.tenant.create({ data: { id: tenantId, name: 'Restaurante Teste', role: 'manager' } });
  await prisma.userTenant.create({ data: { userId, tenantId, role: 'manager' } });
  await prisma.tenantSubscription.create({ data: { tenantId, plan: 'pro', status: 'active' } });

  const req = { tenantId, user: { sub: userId }, role: 'manager', headers: {} } as any;
  const suppliers = new SuppliersController(prisma);
  const finance = new FinanceController(prisma);
  const inventory = new InventoryController(prisma);
  const purchases = new PurchasesController(prisma);
  const reports = new ReportsController(prisma);
  const orders = new OrdersController(
    prisma,
    { emitToTenant: () => {} } as Partial<OrdersGateway> as OrdersGateway,
  );
  const pixWebhook = new PixWebhookController(
    prisma,
    { emitToTenant: () => {} } as Partial<OrdersGateway> as OrdersGateway,
  );

  const supplier = await suppliers.create(req, { name: 'Distribuidora Teste' });
  const category = await finance.createCategory(req, { name: 'Fornecedores' });
  const product = await prisma.product.create({
    data: {
      tenantId,
      name: 'Produto controlado',
      price_cents: 1000,
      cost_cents: 300,
      stock_controlled: true,
      unit: 'unit',
    },
  });

  const purchase = await purchases.create(req, {
    supplier_id: supplier.id,
    document_no: 'NF-001',
    purchased_at: '2026-09-05T12:00:00.000Z',
    create_payable: true,
    expense_category_id: category.id,
    due_date: '2026-09-20T12:00:00.000Z',
    items: [{ product_id: product.id, quantity: 10, unit_cost_cents: 400 }],
  });
  assert.strictEqual(purchase.total_cents, 4000);
  assert.ok(purchase.payableExpense);

  const stocked = await prisma.product.findUniqueOrThrow({ where: { id: product.id } });
  assert.strictEqual(stocked.cost_cents, 400);
  assert.strictEqual(stocked.stock_quantity.toNumber(), 10);

  await inventory.adjust(req, product.id, { type: 'adjustment_out', quantity: 2, notes: 'Perda' });
  const adjusted = await prisma.product.findUniqueOrThrow({ where: { id: product.id } });
  assert.strictEqual(adjusted.stock_quantity.toNumber(), 8);

  const quickSale = await orders.createOrder(
    { ...req, headers: { 'x-idempotency-key': `quick_${runId}` } },
    { order_type: 'quick_sale' },
  );
  const quickSaleWithItem = await orders.addItem(
    { ...req, headers: { 'x-idempotency-key': `quick_item_${runId}` } },
    quickSale.id,
    {
      product_id: product.id,
      quantity: 2,
      selected_options: '[{"name":"Sem gelo"}]',
    },
  );
  assert.strictEqual(quickSaleWithItem.order_type, 'quick_sale');
  assert.strictEqual(quickSaleWithItem.items[0].unit_cost_cents, 400);
  assert.strictEqual(quickSaleWithItem.items[0].selected_options, '[{"name":"Sem gelo"}]');
  const percentagePreview = await orders.previewSettlement(
    req,
    quickSale.id,
    { discount_type: 'percent', discount_value: 1000, service_fee_bps: 0 },
  );
  assert.strictEqual(percentagePreview.discount_cents, 200);
  assert.strictEqual(percentagePreview.total_cents, 1800);
  const pixCharge = await prisma.pixCharge.create({
    data: {
      tenantId,
      orderId: quickSale.id,
      provider: 'test-provider',
      txid: `tx_${runId}`,
      amount_cents: 1800,
      discount_type: 'percent',
      discount_value: 1000,
      discount_cents: 200,
      service_fee_bps: 0,
      copy_paste: 'test-payload',
    },
  });
  process.env.PIX_WEBHOOK_SECRET_TEST_PROVIDER = `secret_${runId}`;
  const webhookBody = { txid: pixCharge.txid, status: 'paid', amount_cents: 1800 };
  const rawBody = Buffer.from(JSON.stringify(webhookBody));
  const timestamp = String(Math.floor(Date.now() / 1000));
  const signature = createHmac('sha256', process.env.PIX_WEBHOOK_SECRET_TEST_PROVIDER)
    .update(`${timestamp}.`)
    .update(rawBody)
    .digest('hex');
  const request = { rawBody } as any;
  const pixResult = await pixWebhook.receive('test-provider', request, signature, timestamp, webhookBody);
  assert.strictEqual(pixResult.ok, true);
  const pixReplay = await pixWebhook.receive(
    'test-provider',
    request,
    signature,
    timestamp,
    webhookBody,
  );
  assert.strictEqual(pixReplay.replayed, true);
  const afterPixStock = await prisma.product.findUniqueOrThrow({ where: { id: product.id } });
  assert.strictEqual(afterPixStock.stock_quantity.toNumber(), 6);

  const recurring = await finance.createRecurring(req, {
    supplier_id: supplier.id,
    category_id: category.id,
    description: 'Aluguel mensal',
    amount_cents: 250000,
    due_day: 10,
    start_date: '2026-01-01T00:00:00.000Z',
  });
  const firstGeneration = await finance.generateRecurring(req, { competence: '2026-09-01T00:00:00.000Z' });
  const secondGeneration = await finance.generateRecurring(req, { competence: '2026-09-01T00:00:00.000Z' });
  assert.strictEqual(firstGeneration.created, 1);
  assert.strictEqual(secondGeneration.created, 0);
  assert.strictEqual(secondGeneration.skipped, 1);

  const generatedExpense = await prisma.payableExpense.findFirstOrThrow({
    where: { tenantId, recurringTemplateId: recurring.id },
  });
  const partiallyPaid = await finance.payExpense(req, generatedExpense.id, {
    amount_cents: 100000,
    paid_at: '2026-09-10T12:00:00.000Z',
    payment_method: 'pix',
  });
  assert.strictEqual(partiallyPaid.status, 'partially_paid');
  assert.strictEqual(partiallyPaid.balance_cents, 150000);

  const order = await prisma.order.create({
    data: {
      tenantId,
      table_label: 'Venda rápida',
      order_type: 'quick_sale',
      status: 'closed',
      subtotal_cents: 3000,
      discount_cents: 300,
      total_cents: 2700,
      settled_at: new Date('2026-09-15T12:00:00.000Z'),
      items: {
        create: {
          productId: product.id,
          product_name: product.name,
          quantity: 3,
          unit_price_cents: 1000,
          unit_cost_cents: 400,
          selected_options: '[{"name":"Sem gelo"}]',
        },
      },
    },
  });
  assert.ok(order.id);

  const margin = await reports.profitMargin(
    req,
    '2026-09-01T00:00:00.000Z',
    '2026-09-30T23:59:59.999Z',
    'product_cost',
    'competence',
  );
  assert.strictEqual(margin.net_revenue_cents, 4500);
  assert.strictEqual(margin.cmv_cents, 2000);
  assert.strictEqual(margin.estimated, true);

  await prisma.$disconnect();
  console.log('Suíte de gestão, estoque, financeiro e relatórios concluída com sucesso!');
}

runManagementPlatformTests().catch((error) => {
  console.error('Management platform test failed:', error);
  process.exit(1);
});
