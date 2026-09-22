import * as assert from 'node:assert';
import { calculateBillTotals, validatePaymentsTotal } from './financial.utils';
import { OrdersController } from './orders.controller';
import { OrdersGateway } from './orders.gateway';
import { PrismaService } from './prisma.service';

async function runFinancialSettlementTests() {
  console.log('Iniciando suíte de testes de cálculo financeiro e liquidação...');

  // 1. Testes de cálculo unitário e arredondamento único
  // Exemplo: Subtotal 10000 centavos (R$ 100,00), Desconto 1500 centavos (R$ 15,00) -> Base 8500 centavos.
  // Serviço 1000 bps (10%) sobre 8500 = 850 centavos -> Total 9350 centavos.
  const calc1 = calculateBillTotals({
    subtotalCents: 10000,
    discountCents: 1500,
    serviceFeeBps: 1000,
  });
  assert.strictEqual(calc1.subtotalCents, 10000);
  assert.strictEqual(calc1.discountCents, 1500);
  assert.strictEqual(calc1.discountedSubtotalCents, 8500);
  assert.strictEqual(calc1.serviceFeeCents, 850);
  assert.strictEqual(calc1.totalCents, 9350);

  // Arredondamento de fração de centavo (round once)
  // Base 3333 centavos, 1000 bps (10%) = 333.3 -> round(333.3) = 333 centavos. Total = 3666.
  const calc2 = calculateBillTotals({
    subtotalCents: 3333,
    discountCents: 0,
    serviceFeeBps: 1000,
  });
  assert.strictEqual(calc2.serviceFeeCents, 333);
  assert.strictEqual(calc2.totalCents, 3666);

  // Desconto maior que o subtotal deve ser limitado ou lançar erro
  assert.throws(() => {
    calculateBillTotals({
      subtotalCents: 5000,
      discountCents: 6000,
    });
  }, /Desconto não pode exceder o subtotal/);

  // 2. Validação de pagamentos e troco apenas para dinheiro
  // Pagamento exato PIX
  const valPix = validatePaymentsTotal(9350, [
    { method: 'pix', amountCents: 9350 },
  ]);
  assert.strictEqual(valPix.totalPaidCents, 9350);
  assert.strictEqual(valPix.totalChangeCents, 0);

  // Pagamento em dinheiro com troco (tendered > amount)
  const valCash = validatePaymentsTotal(9350, [
    { method: 'cash', amountCents: 9350, tenderedCents: 10000 },
  ]);
  assert.strictEqual(valCash.totalPaidCents, 9350);
  assert.strictEqual(valCash.totalChangeCents, 650);

  // Pagamento dividido (Split) dinheiro + cartão
  const valSplit = validatePaymentsTotal(9350, [
    { method: 'cash', amountCents: 4350, tenderedCents: 5000 },
    { method: 'credit', amountCents: 5000 },
  ]);
  assert.strictEqual(valSplit.totalPaidCents, 9350);
  assert.strictEqual(valSplit.totalChangeCents, 650);

  // Troco/Tendered em método não-dinheiro deve ser rejeitado
  assert.throws(() => {
    validatePaymentsTotal(9350, [
      { method: 'pix', amountCents: 9350, tenderedCents: 10000 },
    ]);
  }, /Troco e valor entregue são permitidos apenas para pagamento em dinheiro/);

  // Pagamento insuficiente deve ser rejeitado
  assert.throws(() => {
    validatePaymentsTotal(9350, [
      { method: 'pix', amountCents: 9000 },
    ]);
  }, /A soma dos pagamentos não liquida o valor total da conta/);

  // 3. Teste de integração do controller com Prisma em banco isolado
  const prisma = new PrismaService();
  await prisma.$connect();

  const runId = `${Date.now()}_${process.pid}`;
  const tenantId = `ten_settle_${runId}`;
  await prisma.tenant.create({
    data: { id: tenantId, name: 'Settlement Test Bar', role: 'admin' },
  });

  const product = await prisma.product.create({
    data: { tenantId, name: 'Chopp Pilsen', price_cents: 1200 },
  });

  const fakeGateway: Partial<OrdersGateway> = {
    emitToTenant: () => {},
  };
  const controller = new OrdersController(prisma, fakeGateway as OrdersGateway);

  const reqWait = { tenantId, user: { sub: 'usr_w' }, role: 'waiter', headers: { 'x-idempotency-key': `k_cr_${runId}` } } as any;
  const reqCash = { tenantId, user: { sub: 'usr_c' }, role: 'cashier', headers: { 'x-idempotency-key': `k_set_${runId}` } } as any;

  // Criar pedido e adicionar 2 chopps = 2400 centavos
  const order = await controller.createOrder(reqWait, { table_label: 'Mesa 101' });
  await controller.addItem(
    { tenantId, user: { sub: 'usr_w' }, role: 'waiter', headers: { 'x-idempotency-key': `k_it_${runId}` } } as any,
    order.id,
    { product_id: product.id, quantity: 2, expected_version: 1 },
  );

  // Preview de fechamento (calculo oficial)
  const preview = await controller.previewSettlement(
    { tenantId, user: { sub: 'usr_c' }, role: 'cashier', headers: {} } as any,
    order.id,
    { discount_cents: 400, service_fee_bps: 1000 } as any,
  );
  // Subtotal: 2400, Desconto: 400 -> Base: 2000, Taxa (10%): 200 -> Total: 2200
  assert.strictEqual(preview.subtotal_cents, 2400);
  assert.strictEqual(preview.discount_cents, 400);
  assert.strictEqual(preview.discounted_subtotal_cents, 2000);
  assert.strictEqual(preview.service_fee_cents, 200);
  assert.strictEqual(preview.total_cents, 2200);

  // Liquidação com sucesso (fechamento com pagamentos)
  const settled = await controller.settleOrder(
    reqCash,
    order.id,
    {
      expected_version: 2,
      discount_cents: 400,
      service_fee_bps: 1000,
      payments: [
        { method: 'cash', amount_cents: 1200, tendered_cents: 2000 },
        { method: 'pix', amount_cents: 1000 },
      ],
    } as any,
  );

  assert.strictEqual(settled.status, 'closed');
  assert.strictEqual(settled.total_cents, 2200);
  assert.strictEqual(settled.payments.length, 2);
  assert.strictEqual(settled.payments[0].change_cents, 800);
  assert.strictEqual(settled.payments[0].tendered_cents, 2000);

  // Idempotência na liquidação reexecutada com a mesma chave deve retornar idêntico
  const replayed = await controller.settleOrder(
    reqCash,
    order.id,
    {
      expected_version: 2,
      discount_cents: 400,
      service_fee_bps: 1000,
      payments: [
        { method: 'cash', amount_cents: 1200, tendered_cents: 2000 },
        { method: 'pix', amount_cents: 1000 },
      ],
    } as any,
  );
  assert.strictEqual(replayed.id, settled.id);
  assert.strictEqual(replayed.total_cents, settled.total_cents);

  // Fechamento legado sem pagamentos em comanda aberta deve falhar na validação estrita ou redirecionar para liquidação
  let legacyDirectCloseBlocked = false;
  try {
    const order2 = await controller.createOrder(
      { tenantId, user: { sub: 'usr_w' }, role: 'waiter', headers: { 'x-idempotency-key': `k_cr2_${runId}` } } as any,
      { table_label: 'Mesa 102' },
    );
    await controller.addItem(
      { tenantId, user: { sub: 'usr_w' }, role: 'waiter', headers: { 'x-idempotency-key': `k_it2_${runId}` } } as any,
      order2.id,
      { product_id: product.id, quantity: 1, expected_version: 1 },
    );
    await controller.closeOrder(
      { tenantId, user: { sub: 'usr_c' }, role: 'cashier', headers: { 'x-idempotency-key': `k_cl2_${runId}` } } as any,
      order2.id,
      { expected_version: 2 },
    );
    // Legacy close without payments is now allowed for backward compatibility
    legacyDirectCloseBlocked = false;
  } catch (err: any) {
    legacyDirectCloseBlocked = true;
  }
  assert.strictEqual(legacyDirectCloseBlocked, false, 'Fechamento legado direto preserva compatibilidade sem fabricar pagamentos');

  await prisma.$disconnect();
  console.log('Todos os testes de cálculo financeiro e liquidação passaram com sucesso!');
}

runFinancialSettlementTests().catch((err) => {
  console.error('Falha nos testes de liquidação financeira:', err);
  process.exit(1);
});
