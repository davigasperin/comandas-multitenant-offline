export function validateJwtSecret(secret: string | undefined): string {
  if (!secret) throw new Error('JWT_SECRET is required');
  if (Buffer.byteLength(secret, 'utf8') < 32) throw new Error('JWT_SECRET must be at least 32 bytes');
  return secret;
}

export function parseCorsOrigins(value: string | undefined): ReadonlySet<string> {
  if (!value?.trim()) throw new Error('CORS_ORIGINS is required');
  const origins = value.split(',').map((origin) => origin.trim()).filter(Boolean);
  if (!origins.length || origins.includes('*')) throw new Error('CORS_ORIGINS must be a restricted comma-separated allowlist');
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
