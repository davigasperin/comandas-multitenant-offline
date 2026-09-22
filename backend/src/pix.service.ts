import { Injectable, ServiceUnavailableException } from '@nestjs/common';

export interface PixAdapterChargeInput {
  amountCents: number;
  externalReference: string;
  expiresInSeconds: number;
}

export interface PixAdapterCharge {
  provider: string;
  txid: string;
  qrCode?: string;
  copyPaste: string;
  expiresAt?: Date;
  raw: unknown;
}

@Injectable()
export class PixService {
  async createCharge(input: PixAdapterChargeInput): Promise<PixAdapterCharge> {
    const baseUrl = process.env.PIX_ADAPTER_URL?.replace(/\/$/, '');
    const token = process.env.PIX_ADAPTER_TOKEN;
    const provider = process.env.PIX_PROVIDER?.trim() || 'configured_adapter';
    if (!baseUrl || !token) {
      throw new ServiceUnavailableException(
        'Pix dinâmico não configurado. Defina PIX_ADAPTER_URL e PIX_ADAPTER_TOKEN.',
      );
    }

    let response: Response;
    try {
      response = await fetch(`${baseUrl}/charges`, {
        method: 'POST',
        headers: {
          authorization: `Bearer ${token}`,
          'content-type': 'application/json',
          'x-idempotency-key': input.externalReference,
        },
        body: JSON.stringify({
          amount_cents: input.amountCents,
          external_reference: input.externalReference,
          expires_in_seconds: input.expiresInSeconds,
          webhook_url: process.env.PIX_WEBHOOK_URL,
        }),
      });
    } catch {
      throw new ServiceUnavailableException('Não foi possível conectar ao provedor Pix');
    }

    if (!response.ok) {
      throw new ServiceUnavailableException(`Provedor Pix recusou a cobrança (${response.status})`);
    }
    const raw = await response.json() as Record<string, unknown>;
    const txid = typeof raw.txid === 'string' ? raw.txid : '';
    const copyPaste = typeof raw.copy_paste === 'string' ? raw.copy_paste : '';
    if (!txid || !copyPaste) {
      throw new ServiceUnavailableException('Resposta inválida do provedor Pix');
    }
    const expiresAt = typeof raw.expires_at === 'string' ? new Date(raw.expires_at) : undefined;
    return {
      provider,
      txid,
      copyPaste,
      qrCode: typeof raw.qr_code === 'string' ? raw.qr_code : undefined,
      expiresAt: expiresAt && !Number.isNaN(expiresAt.getTime()) ? expiresAt : undefined,
      raw,
    };
  }
}
