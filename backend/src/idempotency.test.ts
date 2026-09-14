import * as assert from 'node:assert';
import { OrdersController } from './orders.controller';

const controller = new OrdersController();

const req1 = { tenantId: 'ten_test', headers: { 'x-idempotency-key': 'key_123' } };
const res1 = controller.createOrder(req1, { table_label: 'Mesa 99' });
const res2 = controller.createOrder(req1, { table_label: 'Mesa 99' });

assert.strictEqual(res1.id, res2.id, 'Idempotent requests must return identical order');

const req2 = { tenantId: 'ten_test', headers: { 'x-idempotency-key': 'key_item' } };
const item1 = controller.addItem(req2, res1.id, { product_name: 'Suco', quantity: 1 });
const item2 = controller.addItem(req2, res1.id, { product_name: 'Suco', quantity: 1 });

assert.strictEqual(item1.items.length, item2.items.length, 'Idempotent addItem must not duplicate items');

console.log('Backend idempotency tests passed.');
