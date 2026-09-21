import * as assert from 'node:assert';
import { OrdersController } from './orders.controller';
import { PrismaService } from './prisma.service';

async function run() {
  const prisma = new PrismaService();
  await prisma.$connect();

  await prisma.tenant.upsert({
    where: { id: 'ten_test' },
    update: {},
    create: { id: 'ten_test', name: 'Tenant Test', role: 'admin' },
  });

  const controller = new OrdersController(prisma);

  const req1 = { tenantId: 'ten_test', headers: { 'x-idempotency-key': 'key_123' } };
  const res1 = await controller.createOrder(req1 as any, { table_label: 'Mesa 99' });
  const res2 = await controller.createOrder(req1 as any, { table_label: 'Mesa 99' });

  assert.strictEqual(res1.id, res2.id, 'Idempotent requests must return identical order');

  const req2 = { tenantId: 'ten_test', headers: { 'x-idempotency-key': 'key_item' } };
  const item1 = await controller.addItem(req2 as any, res1.id, { product_name: 'Suco', quantity: 1 });
  const item2 = await controller.addItem(req2 as any, res1.id, { product_name: 'Suco', quantity: 1 });

  assert.strictEqual(item1.items.length, item2.items.length, 'Idempotent addItem must not duplicate items');

  console.log('Backend idempotency tests passed.');
  await prisma.$disconnect();
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});
