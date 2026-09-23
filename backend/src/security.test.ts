import * as assert from 'node:assert';
import * as crypto from 'node:crypto';
import { ValidationPipe, BadRequestException, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { hashPassword, verifyPassword, generateRefreshToken, hashToken } from './auth.utils';
import { validateJwtSecret, getCorsOriginValidator, shouldEnableSwagger } from './config.utils';
import { PrismaService } from './prisma.service';
import { AuthService } from './auth.service';
import { migratePlaintextPasswords } from './migrate-passwords';
import { LoginDto, RefreshTokenDto } from './dto/auth.dto';
import { CreateOrderDto, AddItemDto, UpdateOrderStatusDto } from './dto/orders.dto';
import { verifyPixWebhookSignature } from './pix.controller';

async function runSecurityTests() {
  console.log('Iniciando suíte abrangente de segurança P0 e integração...');

  // 1. Password Hashing & Verification Tests
  console.log('1. Testando hash e verificação de senhas...');
  const password = 'StrongPassword!123';
  const hashed = await hashPassword(password);
  assert.ok(hashed.startsWith('scrypt:'), 'Hash must start with scrypt: prefix');

  const validMatch = await verifyPassword(password, hashed);
  assert.strictEqual(validMatch, true, 'Correct password must verify');

  const wrongMatch = await verifyPassword('WrongPassword', hashed);
  assert.strictEqual(wrongMatch, false, 'Wrong password must fail verification');

  const malformedMatch = await verifyPassword(password, 'not-a-valid-scrypt-hash');
  assert.strictEqual(malformedMatch, false, 'Malformed hash must not verify');

  const plaintextMatch = await verifyPassword('password123', 'password123');
  assert.strictEqual(plaintextMatch, false, 'Plaintext stored password must never verify as valid hash');

  // 2. JWT Config Validation Tests
  console.log('2. Testando configuração de ambiente do JWT...');
  assert.throws(() => validateJwtSecret(undefined), /JWT_SECRET/, 'Missing JWT_SECRET must throw');
  assert.throws(() => validateJwtSecret('short-secret'), /deve ter pelo menos 32 bytes/, 'Short JWT_SECRET must throw');
  assert.throws(
    () => validateJwtSecret('troque-por-um-segredo-com-pelo-menos-32-bytes'),
    /valor padrão de exemplo não permitido/,
    'Example JWT secret must throw',
  );
  const validSecret = crypto.randomBytes(32).toString('hex');
  assert.strictEqual(validateJwtSecret(validSecret), validSecret, 'Valid secret >= 32 bytes must pass');
  assert.strictEqual(shouldEnableSwagger('production', 'true'), false, 'Swagger must remain disabled in production');
  assert.strictEqual(shouldEnableSwagger('development', 'true'), true, 'Swagger can be enabled outside production');

  // 3. CORS Origin Validation Tests
  console.log('3. Testando validação de origem CORS...');
  const corsChecker = getCorsOriginValidator('http://localhost:3000,http://app.example.com');
  assert.strictEqual(corsChecker(undefined), true, 'Non-browser / mobile requests must be allowed');
  assert.strictEqual(corsChecker('http://localhost:3000'), true, 'Allowed origin must return true');
  assert.strictEqual(corsChecker('http://malicious-site.com'), false, 'Unauthorized origin must return false');

  const provider = 'test-provider';
  const webhookSecret = crypto.randomBytes(32).toString('hex');
  process.env.PIX_WEBHOOK_SECRET_TEST_PROVIDER = webhookSecret;
  const timestamp = String(Math.floor(Date.now() / 1000));
  const rawBody = Buffer.from('{"txid":"tx1","status":"paid"}');
  const signature = crypto.createHmac('sha256', webhookSecret).update(`${timestamp}.`).update(rawBody).digest('hex');
  assert.doesNotThrow(() => verifyPixWebhookSignature({ provider, rawBody, timestamp, signature }));
  assert.throws(
    () => verifyPixWebhookSignature({ provider, rawBody: Buffer.from('{}'), timestamp, signature }),
    /não autorizado/,
  );
  assert.throws(
    () => verifyPixWebhookSignature({ provider, rawBody, timestamp: String(Number(timestamp) - 301), signature }),
    /não autorizado/,
  );
  delete process.env.PIX_WEBHOOK_SECRET_TEST_PROVIDER;

  // 4. DTO ValidationPipe Tests
  console.log('4. Testando pipe de validação dos DTOs em tempo de execução...');
  const pipe = new ValidationPipe({
    whitelist: true,
    forbidNonWhitelisted: true,
    transform: true,
  });

  let rejectedExtraProps = false;
  try {
    await pipe.transform(
      { email: 'test@example.com', password: 'password123', extraField: 'malicious' },
      { type: 'body', metatype: LoginDto },
    );
  } catch (err) {
    if (err instanceof BadRequestException) rejectedExtraProps = true;
  }
  assert.strictEqual(rejectedExtraProps, true, 'ValidationPipe must reject extra properties in LoginDto');

  // 5. Database, Migration & AuthService Integration Tests (Isolated Test DB)
  console.log('5. Testando migração do banco e fluxo do serviço de autenticação...');
  const prisma = new PrismaService();
  await prisma.$connect();
  const runId = `${Date.now()}_${process.pid}`;
  const legacyEmail = `legacy_${runId}@example.com`;

  await prisma.user.create({
    data: {
      id: `usr_legacy_${runId}`,
      name: 'Legacy User',
      email: legacyEmail,
      password: 'plainpassword123',
    },
  });

  const legacyCheckBefore = await prisma.user.findUnique({ where: { email: legacyEmail } });
  assert.strictEqual(legacyCheckBefore?.password, 'plainpassword123');

  // Run explicit password migration conversion
  const migrationResult = await migratePlaintextPasswords(prisma);
  assert.ok(migrationResult.migrated >= 1, 'Must migrate at least one plaintext password');

  const legacyCheckAfter = await prisma.user.findUnique({ where: { email: legacyEmail } });
  assert.ok(legacyCheckAfter?.password.startsWith('scrypt:'), 'Legacy password must be converted to scrypt hash');

  // Test AuthService login, refresh rotation, and logout
  const jwt = new JwtService({ secret: validSecret });
  const authService = new AuthService(prisma, jwt);

  // Update legacy user password hash to known test password for login test
  const testLoginPassword = 'SecureLoginPass!99';
  const hashedLoginPass = await hashPassword(testLoginPassword);
  await prisma.user.update({
    where: { email: legacyEmail },
    data: { password: hashedLoginPass },
  });

  // Test invalid login
  let invalidLoginFailed = false;
  try {
    await authService.login(legacyEmail, 'WrongPassword!');
  } catch (err) {
    if (err instanceof UnauthorizedException) invalidLoginFailed = true;
  }
  assert.strictEqual(invalidLoginFailed, true, 'Invalid password must throw UnauthorizedException');

  const session = await authService.login(legacyEmail, testLoginPassword);
  assert.ok(session.access_token);
  assert.ok(session.refresh_token);

  // Test refresh token rotation (strict single-use)
  const refreshed = await authService.refresh(session.refresh_token);
  assert.ok(refreshed.access_token);
  assert.ok(refreshed.refresh_token);
  assert.notStrictEqual(refreshed.refresh_token, session.refresh_token, 'Refresh token must rotate');

  // Test reuse attack: presenting the already-rotated token must immediately fail and revoke session family
  let reuseDetected = false;
  try {
    await authService.refresh(session.refresh_token);
  } catch (err) {
    if (err instanceof UnauthorizedException) reuseDetected = true;
  }
  assert.strictEqual(reuseDetected, true, 'Reuse of rotated token must throw UnauthorizedException');

  // Verify all user tokens were revoked after reuse attack
  const remainingActiveTokens = await prisma.refreshToken.count({
    where: { userId: session.user.id, revokedAt: null },
  });
  assert.strictEqual(remainingActiveTokens, 0, 'Reuse attack must revoke all active refresh tokens for user');

  // Verify the previously issued token is now also invalidated due to reuse detection
  let cascadeRevocationConfirmed = false;
  try {
    await authService.refresh(refreshed.refresh_token);
  } catch (err) {
    if (err instanceof UnauthorizedException) cascadeRevocationConfirmed = true;
  }
  assert.strictEqual(cascadeRevocationConfirmed, true, 'Token family must be revoked after reuse');

  // Log in fresh for logout test
  const freshSession = await authService.login(legacyEmail, testLoginPassword);
  assert.ok(freshSession.refresh_token);

  // Test logout
  await authService.logout(freshSession.refresh_token);
  let logoutRefreshFailed = false;
  try {
    await authService.refresh(freshSession.refresh_token);
  } catch (err) {
    if (err instanceof UnauthorizedException) logoutRefreshFailed = true;
  }
  assert.strictEqual(logoutRefreshFailed, true, 'Using a logged-out refresh token must throw Unauthorized');

  await prisma.$disconnect();
  console.log('Todos os testes abrangentes de segurança P0 e integração foram concluídos com sucesso!');
}

runSecurityTests().catch((err) => {
  console.error('Falha nos testes de segurança e integração:', err);
  process.exit(1);
});
