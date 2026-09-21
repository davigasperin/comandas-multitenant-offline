import * as assert from 'node:assert';
import * as crypto from 'node:crypto';
import { ValidationPipe, BadRequestException, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { hashPassword, verifyPassword, generateRefreshToken, hashToken } from './auth.utils';
import { validateJwtSecret, getCorsOriginValidator } from './config.utils';
import { PrismaService } from './prisma.service';
import { AuthService } from './auth.service';
import { migratePlaintextPasswords } from './migrate-passwords';
import { LoginDto, RefreshTokenDto } from './dto/auth.dto';
import { CreateOrderDto, AddItemDto, UpdateOrderStatusDto } from './dto/orders.dto';

async function runSecurityTests() {
  console.log('Running Comprehensive Security P0 & Integration Test Suite...');

  // 1. Password Hashing & Verification Tests
  console.log('1. Testing Password Hashing & Verification...');
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
  console.log('2. Testing JWT Env Configuration...');
  assert.throws(() => validateJwtSecret(undefined), /JWT_SECRET/, 'Missing JWT_SECRET must throw');
  assert.throws(() => validateJwtSecret('short-secret'), /at least 32 bytes/, 'Short JWT_SECRET must throw');
  const validSecret = '1234567890123456789012345678901234567890';
  assert.strictEqual(validateJwtSecret(validSecret), validSecret, 'Valid secret >= 32 bytes must pass');

  // 3. CORS Origin Validation Tests
  console.log('3. Testing CORS Origin Validation...');
  const corsChecker = getCorsOriginValidator('http://localhost:3000,http://app.example.com');
  assert.strictEqual(corsChecker(undefined), true, 'Non-browser / mobile requests must be allowed');
  assert.strictEqual(corsChecker('http://localhost:3000'), true, 'Allowed origin must return true');
  assert.strictEqual(corsChecker('http://malicious-site.com'), false, 'Unauthorized origin must return false');

  // 4. DTO ValidationPipe Tests
  console.log('4. Testing DTO Runtime Validation Pipe...');
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
  console.log('5. Testing Database Migration & AuthService Flow...');
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

  const session = await authService.login(legacyEmail, testLoginPassword);
  assert.ok(session.access_token);
  assert.ok(session.refresh_token);

  // Test refresh token rotation
  const refreshed = await authService.refresh(session.refresh_token);
  assert.ok(refreshed.access_token);
  assert.ok(refreshed.refresh_token);
  assert.notStrictEqual(refreshed.refresh_token, session.refresh_token, 'Refresh token must rotate');

  // Test concurrent refresh with old token within grace window
  const concurrentRefresh = await authService.refresh(session.refresh_token);
  assert.ok(concurrentRefresh.access_token, 'Concurrent refresh within grace window must succeed');
  assert.ok(concurrentRefresh.refresh_token);

  // Test reuse attack outside grace window: manually backdate revokedAt
  await prisma.refreshToken.updateMany({
    where: { tokenHash: hashToken(session.refresh_token) },
    data: { revokedAt: new Date(Date.now() - 30000) },
  });

  let reuseDetected = false;
  try {
    await authService.refresh(session.refresh_token);
  } catch (err) {
    if (err instanceof UnauthorizedException) reuseDetected = true;
  }
  assert.strictEqual(reuseDetected, true, 'Reuse attack outside grace window must throw Unauthorized');

  // Verify all user tokens were revoked after reuse attack
  const remainingActiveTokens = await prisma.refreshToken.count({
    where: { userId: session.user.id, revokedAt: null },
  });
  assert.strictEqual(remainingActiveTokens, 0, 'Reuse attack must revoke all active refresh tokens for user');

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
  console.log('All Comprehensive Security P0 & Integration tests passed successfully!');
}

runSecurityTests().catch((err) => {
  console.error('Security & Integration Tests Failed:', err);
  process.exit(1);
});
