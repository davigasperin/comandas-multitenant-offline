import * as assert from 'node:assert';
import { JwtService } from '@nestjs/jwt';
import { OrdersController } from './orders.controller';
import { OrdersGateway } from './orders.gateway';
import { PrismaService } from './prisma.service';

async function run() {
  const prisma = new PrismaService();
  await prisma.$connect();

  const runId = `${Date.now()}_${process.pid}`;
  const tenantId = `ten_test_${runId}`;
  await prisma.tenant.create({
    data: { id: tenantId, name: 'Empresa de teste', role: 'admin' },
  });

  const emittedEvents: Array<{ tenantId: string; event: string; data: any }> = [];
  const fakeGateway: Partial<OrdersGateway> = {
    emitToTenant: (tenantId: string, event: string, data: unknown) => {
      emittedEvents.push({ tenantId, event, data });
    },
  };

  const controller = new OrdersController(prisma, fakeGateway as OrdersGateway);

  const req1 = { tenantId: tenantId, headers: { 'x-idempotency-key': 'key_create_1' } };
  const res1 = await controller.createOrder(req1 as any, { table_label: 'Mesa 10' });
  const res2 = await controller.createOrder(req1 as any, { table_label: 'Mesa 10' });
  assert.strictEqual(res1.id, res2.id, 'Idempotent createOrder must return identical order');

  let rejectedReuse = false;
  try {
    await controller.createOrder(req1 as any, { table_label: 'Mesa 20' });
  } catch (err: any) {
    if (err?.status === 409 || err?.response?.statusCode === 409) {
      rejectedReuse = true;
    }
  }
  assert.strictEqual(rejectedReuse, true, 'Reusing idempotency key with different payload must throw 409');

  const patch1 = await controller.updateOrderStatus(
    { tenantId: tenantId, headers: { 'x-idempotency-key': 'key_status_1' } } as any,
    res1.id,
    { status: 'sentToKitchen' },
  );
  assert.strictEqual(patch1.status, 'sentToKitchen');

  const patch2 = await controller.updateOrderStatus(
    { tenantId: tenantId, headers: { 'x-idempotency-key': 'key_status_2' } } as any,
    res1.id,
    { status: 'delivered' },
  );
  assert.strictEqual(patch2.status, 'delivered');

  let invalidTransitionRejected = false;
  try {
    await controller.updateOrderStatus(
      { tenantId: tenantId, headers: {} } as any,
      res1.id,
      { status: 'sentToKitchen' },
    );
  } catch (err: any) {
    invalidTransitionRejected = true;
  }
  assert.strictEqual(invalidTransitionRejected, true, 'Invalid backward transition must be rejected');

  assert.ok(emittedEvents.some((e) => e.event === 'order:created' && e.data.id === res1.id));
  assert.ok(emittedEvents.some((e) => e.event === 'order:updated' && e.data.status === 'delivered'));

  // Teste de autenticação do gateway e associação à empresa
  const testSecret = '1234567890123456789012345678901234567890';
  const allowedOrigin = (process.env.CORS_ORIGINS ?? 'http://localhost:3000').split(',')[0].trim();
  const jwt = new JwtService({ secret: testSecret });
  const realGateway = new OrdersGateway(jwt, prisma);

  let disconnected = false;
  let joinedRoom: string | null = null;
  const mockClient: any = {
    handshake: { headers: { origin: allowedOrigin }, auth: { token: 'invalid_token', tenantId: tenantId } },
    data: {},
    join: async (room: string) => { joinedRoom = room; },
    disconnect: () => { disconnected = true; },
  };
  await realGateway.handleConnection(mockClient);
  assert.strictEqual(disconnected, true, 'Invalid token must disconnect client');

  // Teste de token válido com associação válida à empresa
  const testUserId = `usr_test_${runId}`;
  await prisma.user.create({
    data: {
      id: testUserId,
      name: 'Test Gateway User',
      email: `gw_${runId}@example.com`,
      password: 'scrypt:00:11',
    },
  });
  await prisma.userTenant.create({
    data: {
      userId: testUserId,
      tenantId: tenantId,
      role: 'waiter',
    },
  });

  const validToken = await jwt.signAsync({ sub: testUserId, email: `gw_${runId}@example.com` }, { expiresIn: '1h' });
  let validDisconnected = false;
  let validJoinedRoom: string | null = null;
  const mockValidClient: any = {
    handshake: { headers: { origin: allowedOrigin }, auth: { token: validToken, tenantId: tenantId } },
    data: {},
    join: async (room: string) => { validJoinedRoom = room; },
    disconnect: () => { validDisconnected = true; },
  };
  await realGateway.handleConnection(mockValidClient);
  assert.strictEqual(validDisconnected, false, 'Valid client must not disconnect');
  assert.strictEqual(validJoinedRoom, tenantId, 'Valid client must join tenant room');

  console.log('Testes do controlador de pedidos, idempotência e gateway concluídos.');
  await prisma.$disconnect();
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});
