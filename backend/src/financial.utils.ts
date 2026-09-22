import { BadRequestException } from '@nestjs/common';

export type PaymentMethod = 'cash' | 'pix' | 'credit' | 'debit' | 'voucher';

export interface BillCalculationInput {
  subtotalCents: number;
  discountCents?: number;
  serviceFeeBps?: number;
}

export interface BillCalculationResult {
  subtotalCents: number;
  discountCents: number;
  discountedSubtotalCents: number;
  serviceFeeBps: number;
  serviceFeeCents: number;
  totalCents: number;
}

export interface PaymentInput {
  method: PaymentMethod;
  amountCents: number;
  tenderedCents?: number;
}

export interface ValidatedPayment {
  method: PaymentMethod;
  amountCents: number;
  tenderedCents?: number;
  changeCents: number;
}

export interface PaymentValidationResult {
  totalPaidCents: number;
  totalChangeCents: number;
  payments: ValidatedPayment[];
}

export function calculateBillTotals(input: BillCalculationInput): BillCalculationResult {
  const subtotalCents = Math.max(0, Math.floor(input.subtotalCents));
  const discountCents = Math.max(0, Math.floor(input.discountCents ?? 0));
  const serviceFeeBps = Math.max(0, Math.floor(input.serviceFeeBps ?? 1000)); // Padrão 10% (1000 bps)

  if (discountCents > subtotalCents) {
    throw new BadRequestException('Desconto não pode exceder o subtotal');
  }

  const discountedSubtotalCents = subtotalCents - discountCents;
  // Arredondamento único (round once) para centavos inteiros
  const serviceFeeCents = Math.round((discountedSubtotalCents * serviceFeeBps) / 10000);
  const totalCents = discountedSubtotalCents + serviceFeeCents;

  return {
    subtotalCents,
    discountCents,
    discountedSubtotalCents,
    serviceFeeBps,
    serviceFeeCents,
    totalCents,
  };
}

export function validatePaymentsTotal(expectedTotalCents: number, payments: PaymentInput[]): PaymentValidationResult {
  if (!Array.isArray(payments) || payments.length === 0) {
    throw new BadRequestException('Pelo menos um pagamento deve ser informado para liquidação');
  }

  let totalPaidCents = 0;
  let totalChangeCents = 0;
  const validatedPayments: ValidatedPayment[] = [];

  for (const p of payments) {
    const amount = Math.floor(p.amountCents);
    if (!Number.isInteger(amount) || amount <= 0) {
      throw new BadRequestException('O valor de cada pagamento deve ser um número inteiro positivo em centavos');
    }

    if (!['cash', 'pix', 'credit', 'debit', 'voucher'].includes(p.method)) {
      throw new BadRequestException(`Método de pagamento inválido: ${p.method}`);
    }

    let change = 0;
    let tendered = p.tenderedCents !== undefined ? Math.floor(p.tenderedCents) : undefined;

    if (p.method === 'cash') {
      if (tendered !== undefined) {
        if (!Number.isInteger(tendered) || tendered < amount) {
          throw new BadRequestException('Valor entregue em dinheiro deve ser maior ou igual ao valor pago');
        }
        change = tendered - amount;
      } else {
        tendered = amount;
      }
    } else {
      if (tendered !== undefined && tendered !== amount) {
        throw new BadRequestException('Troco e valor entregue são permitidos apenas para pagamento em dinheiro');
      }
    }

    totalPaidCents += amount;
    totalChangeCents += change;

    validatedPayments.push({
      method: p.method,
      amountCents: amount,
      tenderedCents: tendered,
      changeCents: change,
    });
  }

  if (totalPaidCents !== expectedTotalCents) {
    throw new BadRequestException(
      `A soma dos pagamentos não liquida o valor total da conta. Total esperado: ${expectedTotalCents} centavos, Total informado: ${totalPaidCents} centavos`,
    );
  }

  return {
    totalPaidCents,
    totalChangeCents,
    payments: validatedPayments,
  };
}
