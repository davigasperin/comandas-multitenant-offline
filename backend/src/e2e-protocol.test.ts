import * as assert from 'node:assert';
import * as path from 'node:path';
import * as fs from 'node:fs';
import { randomBytes } from 'node:crypto';
import { execSync } from 'node:child_process';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { io as Client, Socket } from 'socket.io-client';
import { getCorsOptions } from './config.utils';
import { PrismaService } from './prisma.service';
import { hashPassword } from './auth.utils';
import { JwtService } from '@nestjs/jwt';

async function runE2eSuite() {
  console.log('Iniciando suíte E2E de protocolo e segurança...');

  const tempDbName = `test_e2e_${Date.now()}_${process.pid}.db`;
  const tempDbPath = path.resolve(__dirname, `../prisma/${tempDbName}`);
  const tempDbUrl = `file:${tempDbPath.replace(/\\/g, '/')}`;

  process.env.DATABASE_URL = tempDbUrl;
  const ephemeralSecret = randomBytes(32).toString('hex');
  process.env.JWT_SECRET = ephemeralSecret;
  process.env.CORS_ORIGINS = 'http://localhost:3000,http://app.comandas.local';
  process.env.PORT = '0';

  execSync('npx prisma migrate deploy', {
    cwd: path.resolve(__dirname, '..'),
    env: { ...process.env, DATABASE_URL: tempDbUrl },
    stdio: 'pipe',
  });

  const { AppModule } = await import('./app.module');
  const { NestFactory } = await import('@nestjs/core');

  const app: INestApplication = await NestFactory.create(AppModule, { cors: getCorsOptions(process.env.CORS_ORIGINS) });
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }));

  await app.listen(0);
  const server = app.getHttpServer();
  const address = server.address();
  const port = typeof address === 'object' && address !== null ? address.port : 3000;
  const baseUrl = `http://127.0.0.1:${port}/v1`;
  const wsUrl = `http://127.0.0.1:${port}/orders`;

  const prisma = new PrismaService();
  await prisma.$connect();

  const openSockets: Socket[] = [];

  try {
    const runId = `${Date.now()}_${randomBytes(4).toString('hex')}`;
    const userEmail = `e2e_${runId}@comandas.local`;
    const rawPassword = `SecPass_${runId}!99`;
    const hashedPassword = await hashPassword(rawPassword);

    const user = await prisma.user.create({
      data: {
        id: `usr_e2e_${runId}`,
        name: 'E2E User',
        email: userEmail,
        password: hashedPassword,
      },
    });

    const tenantAllowed = await prisma.tenant.create({
      data: {
        id: `ten_allowed_${runId}`,
        name: 'Allowed Restaurant',
        role: 'restaurant',
      },
    });

    const tenantForbidden = await prisma.tenant.create({
      data: {
        id: `ten_forbidden_${runId}`,
        name: 'Forbidden Restaurant',
        role: 'restaurant',
      },
    });

    const tenantOther = await prisma.tenant.create({
      data: {
        id: `ten_other_${runId}`,
        name: 'Other Restaurant',
        role: 'restaurant',
      },
    });

    await prisma.userTenant.create({
      data: {
        userId: user.id,
        tenantId: tenantAllowed.id,
        role: 'admin',
      },
    });

    await prisma.userTenant.create({
      data: {
        userId: user.id,
        tenantId: tenantOther.id,
        role: 'staff',
      },
    });

    console.log('Testando CORS HTTP...');
    const corsAllowedRes = await fetch(`${baseUrl}/health`, {
      method: 'GET',
      headers: { Origin: 'http://localhost:3000' },
    });
    assert.strictEqual(corsAllowedRes.headers.get('access-control-allow-origin'), 'http://localhost:3000');

    const corsDeniedRes = await fetch(`${baseUrl}/health`, {
      method: 'GET',
      headers: { Origin: 'http://malicious-origin.com' },
    });
    assert.strictEqual(corsDeniedRes.headers.get('access-control-allow-origin'), null);

    console.log('Testando autenticação de login...');
    const invalidLoginRes = await fetch(`${baseUrl}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Origin: 'http://localhost:3000' },
      body: JSON.stringify({ email: userEmail, password: 'WrongPassword' }),
    });
    assert.strictEqual(invalidLoginRes.status, 401);

    const loginRes = await fetch(`${baseUrl}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Origin: 'http://localhost:3000' },
      body: JSON.stringify({ email: userEmail, password: rawPassword }),
    });
    assert.strictEqual(loginRes.status, 201);
    const loginData = await loginRes.json();
    assert.ok(loginData.access_token);
    assert.ok(loginData.refresh_token);

    console.log('Testando concorrência de renovação com uso único estrito...');
    const refresh1Promise = fetch(`${baseUrl}/auth/refresh`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Origin: 'http://localhost:3000' },
      body: JSON.stringify({ refresh_token: loginData.refresh_token }),
    });
    const refresh2Promise = fetch(`${baseUrl}/auth/refresh`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Origin: 'http://localhost:3000' },
      body: JSON.stringify({ refresh_token: loginData.refresh_token }),
    });
    const [ref1Res, ref2Res] = await Promise.all([refresh1Promise, refresh2Promise]);
    const statuses = [ref1Res.status, ref2Res.status].sort();
    assert.deepStrictEqual(statuses, [201, 401], 'Strict single-use must allow exactly one refresh and reject concurrent replay with 401');

    const successfulRefRes = ref1Res.status === 201 ? ref1Res : ref2Res;
    const refData = await successfulRefRes.json();
    assert.ok(refData.access_token);
    assert.ok(refData.refresh_token);

    console.log('Testando isolamento de empresas via REST...');
    const forbiddenTenantRes = await fetch(`${baseUrl}/orders`, {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${loginData.access_token}`,
        'X-Tenant-Id': tenantForbidden.id,
        Origin: 'http://localhost:3000',
      },
    });
    assert.strictEqual(forbiddenTenantRes.status, 403);

    const allowedTenantRes = await fetch(`${baseUrl}/orders`, {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${loginData.access_token}`,
        'X-Tenant-Id': tenantAllowed.id,
        Origin: 'http://localhost:3000',
      },
    });
    assert.strictEqual(allowedTenantRes.status, 200);

    console.log('Testando encerramento de sessão...');
    const logoutRes = await fetch(`${baseUrl}/auth/logout`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Origin: 'http://localhost:3000' },
      body: JSON.stringify({ refresh_token: refData.refresh_token }),
    });
    assert.strictEqual(logoutRes.status, 201);

    const postLogoutRefresh = await fetch(`${baseUrl}/auth/refresh`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Origin: 'http://localhost:3000' },
      body: JSON.stringify({ refresh_token: refData.refresh_token }),
    });
    assert.strictEqual(postLogoutRefresh.status, 401);

    console.log('Testando segurança e gateway WebSocket...');

    const socketAuth = Client(wsUrl, {
      transports: ['websocket'],
      auth: { token: loginData.access_token, tenantId: tenantAllowed.id },
      extraHeaders: { Origin: 'http://localhost:3000' },
      reconnection: false,
    });
    openSockets.push(socketAuth);

    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Auth socket authentication timeout')), 3000);
      socketAuth.on('authenticated', () => {
        clearTimeout(timer);
        resolve();
      });
      socketAuth.on('connect_error', (err) => {
        clearTimeout(timer);
        reject(err);
      });
      socketAuth.on('disconnect', () => {
        clearTimeout(timer);
        reject(new Error('Auth socket disconnected before authentication'));
      });
    });

    let broadcastReceived = false;
    socketAuth.on('order:created', (data: any) => {
      if (data?.id === 'ord_e2e_test_999') {
        broadcastReceived = true;
      }
    });

    const { OrdersGateway } = await import('./orders.gateway');
    const gateway = app.get(OrdersGateway);
    gateway.emitToTenant(tenantAllowed.id, 'order:created', { id: 'ord_e2e_test_999', status: 'open' });

    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        if (broadcastReceived) resolve();
        else reject(new Error('Timeout waiting for broadcast event on authorized socket'));
      }, 1500);
      const check = setInterval(() => {
        if (broadcastReceived) {
          clearInterval(check);
          clearTimeout(timer);
          resolve();
        }
      }, 50);
    });
    assert.strictEqual(broadcastReceived, true, 'Authorized client must receive broadcast event');

    const socketOther = Client(wsUrl, {
      transports: ['websocket'],
      auth: { token: loginData.access_token, tenantId: tenantOther.id },
      extraHeaders: { Origin: 'http://localhost:3000' },
      reconnection: false,
    });
    openSockets.push(socketOther);

    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Other tenant socket connect timeout')), 3000);
      socketOther.on('connect', () => {
        clearTimeout(timer);
        resolve();
      });
      socketOther.on('connect_error', (err) => {
        clearTimeout(timer);
        reject(err);
      });
    });

    let otherReceived = false;
    socketOther.on('order:created', () => {
      otherReceived = true;
    });

    gateway.emitToTenant(tenantAllowed.id, 'order:created', { id: 'ord_e2e_cross_tenant', status: 'open' });
    await new Promise((r) => setTimeout(r, 400));
    assert.strictEqual(otherReceived, false, 'Cross-tenant client must not receive events from another tenant room');

    const testRejection = async (authObj: any, extraHeaders?: any): Promise<void> => {
      return new Promise((resolve, reject) => {
        const sock = Client(wsUrl, {
          transports: ['websocket'],
          auth: authObj,
          extraHeaders: extraHeaders || { Origin: 'http://localhost:3000' },
          reconnection: false,
        });
        openSockets.push(sock);

        const timer = setTimeout(() => {
          sock.close();
          reject(new Error('Expected socket connection rejection but timed out connected'));
        }, 3000);

        sock.on('disconnect', () => {
          clearTimeout(timer);
          sock.close();
          resolve();
        });

        sock.on('connect_error', () => {
          clearTimeout(timer);
          sock.close();
          resolve();
        });
      });
    };

    await testRejection({ token: loginData.access_token, tenantId: tenantForbidden.id });
    await testRejection({ token: 'invalid.jwt.token', tenantId: tenantAllowed.id });
    const jwtService = new JwtService({ secret: ephemeralSecret });
    const expiredToken = await jwtService.signAsync(
      { sub: user.id, email: user.email },
      { expiresIn: '-10s' }
    );
    await testRejection({ token: expiredToken, tenantId: tenantAllowed.id });
    await testRejection(
      { token: loginData.access_token, tenantId: tenantAllowed.id },
      { Origin: 'http://malicious-origin.com' }
    );

    console.log('Suíte E2E de protocolo e segurança concluída com sucesso!');
  } finally {
    for (const s of openSockets) {
      try {
        if (s.connected || !s.disconnected) s.close();
      } catch {}
    }
    await app.close();
    await prisma.$disconnect();
    try {
      if (fs.existsSync(tempDbPath)) fs.unlinkSync(tempDbPath);
      if (fs.existsSync(`${tempDbPath}-journal`)) fs.unlinkSync(`${tempDbPath}-journal`);
    } catch {}
  }
}

runE2eSuite().catch((err) => {
  console.error('Falha na suíte E2E de protocolo e segurança:', err);
  process.exit(1);
});
