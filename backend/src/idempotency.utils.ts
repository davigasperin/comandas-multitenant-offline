import * as crypto from 'node:crypto';
import { BadRequestException, ConflictException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from './prisma.service';

export function getIdempotencyKey(headers: Record<string, string | string[] | undefined>): string | undefined {
  const rawKey = headers['x-idempotency-key'];
  return Array.isArray(rawKey) ? rawKey[0]?.trim() : rawKey?.trim();
}

export function computePayloadHash(payload: unknown): string {
  return crypto.createHash('sha256').update(JSON.stringify(payload ?? {})).digest('hex');
}

export async function executeIdempotent<T>(
  prisma: PrismaService,
  tenantId: string,
  key: string | undefined,
  operation: string,
  payload: unknown,
  userId: string | undefined,
  mutate: (tx: Prisma.TransactionClient) => Promise<T>,
): Promise<{ value: T; replayed: boolean }> {
  if (!key) throw new BadRequestException('X-Idempotency-Key é obrigatório e deve ser único');

  const requestHash = computePayloadHash({ operation, tenantId, userId: userId ?? null, payload });
  const existing = await prisma.idempotencyKey.findUnique({
    where: { tenantId_key: { tenantId, key } },
  });

  if (existing) {
    if (existing.requestHash !== requestHash) {
      throw new ConflictException('Chave de idempotência já utilizada em outra operação');
    }
    if (existing.status === 'completed' && existing.response) {
      return { value: JSON.parse(existing.response) as T, replayed: true };
    }
    throw new ConflictException('Operação com esta chave ainda está sendo processada');
  }

  try {
    const value = await prisma.$transaction(async (tx) => {
      await tx.idempotencyKey.create({
        data: { tenantId, key, status: 'processing', requestHash },
      });
      const result = await mutate(tx);
      await tx.idempotencyKey.update({
        where: { tenantId_key: { tenantId, key } },
        data: { status: 'completed', response: JSON.stringify(result), completed_at: new Date() },
      });
      return result;
    });
    return { value, replayed: false };
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
      const canonical = await prisma.idempotencyKey.findUnique({
        where: { tenantId_key: { tenantId, key } },
      });
      if (canonical?.requestHash !== requestHash) {
        throw new ConflictException('Chave de idempotência já utilizada em outra operação');
      }
      if (canonical?.status === 'completed' && canonical.response) {
        return { value: JSON.parse(canonical.response) as T, replayed: true };
      }
      throw new ConflictException('Operação concorrente ainda está sendo processada');
    }
    throw error;
  }
}
