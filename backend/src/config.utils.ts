const FORBIDDEN_JWT_SECRETS = new Set([
  'troque-por-um-segredo-com-pelo-menos-32-bytes',
  '1234567890123456789012345678901234567890',
  'secret-key-123456789012345678901234567890',
]);

export function validateJwtSecret(secret: string | undefined): string {
  if (!secret) throw new Error('JWT_SECRET é obrigatório');
  const trimmed = secret.trim();
  if (Buffer.byteLength(trimmed, 'utf8') < 32) throw new Error('JWT_SECRET deve ter pelo menos 32 bytes');
  if (FORBIDDEN_JWT_SECRETS.has(trimmed)) {
    throw new Error('JWT_SECRET inseguro: valor padrão de exemplo não permitido');
  }
  return trimmed;
}

export function parseCorsOrigins(value: string | undefined): ReadonlySet<string> {
  if (!value?.trim()) throw new Error('CORS_ORIGINS é obrigatório');
  const origins = value.split(',').map((origin) => origin.trim()).filter(Boolean);
  if (!origins.length || origins.includes('*')) throw new Error('CORS_ORIGINS deve ser uma lista restrita separada por vírgulas');
  return new Set(origins);
}

export function getCorsOriginValidator(value: string | undefined): (origin: string | undefined) => boolean {
  const allowed = parseCorsOrigins(value);
  return (origin) => origin === undefined || allowed.has(origin);
}

export type CorsOriginCallback = (err: Error | null, allow?: boolean) => void;

export function createCorsOriginCallback(
  value: string | undefined,
): (origin: string | undefined, callback: CorsOriginCallback) => void {
  const validator = getCorsOriginValidator(value);
  return (origin, callback) => {
    callback(null, validator(origin));
  };
}

export function getCorsOptions(value: string | undefined) {
  return {
    origin: createCorsOriginCallback(value),
    credentials: false,
  };
}
