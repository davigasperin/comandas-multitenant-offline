import { BadRequestException } from '@nestjs/common';

export function pageArgs(limit?: string, cursor?: string) {
  const parsed = limit === undefined ? 50 : Number(limit);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 100) {
    throw new BadRequestException('limit deve ser inteiro entre 1 e 100');
  }
  return { take: parsed + 1, ...(cursor ? { skip: 1, cursor: { id: cursor } } : {}) };
}

export function pageResult<T extends { id: string }>(rows: T[], limit?: string) {
  const size = limit === undefined ? 50 : Number(limit);
  const hasNext = rows.length > size;
  if (hasNext) rows.pop();
  return { data: rows, pagination: { limit: size, next_cursor: hasNext ? rows.at(-1)?.id ?? null : null } };
}
