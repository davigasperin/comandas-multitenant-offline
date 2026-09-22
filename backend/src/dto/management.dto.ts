import { Type } from 'class-transformer';
import {
  IsArray,
  IsBoolean,
  IsDateString,
  IsEmail,
  IsIn,
  IsInt,
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  Min,
  ValidateNested,
} from 'class-validator';

export class CreateSupplierDto {
  @IsString() @IsNotEmpty() name!: string;
  @IsOptional() @IsString() trade_name?: string;
  @IsOptional() @IsString() document?: string;
  @IsOptional() @IsString() phone?: string;
  @IsOptional() @IsEmail() email?: string;
  @IsOptional() @IsString() notes?: string;
}

export class UpdateSupplierDto extends CreateSupplierDto {
  @IsOptional() @IsString() declare name: string;
  @IsOptional() @IsBoolean() active?: boolean;
}

export class CreateExpenseCategoryDto {
  @IsString() @IsNotEmpty() name!: string;
}

export class UpdateExpenseCategoryDto {
  @IsOptional() @IsString() @IsNotEmpty() name?: string;
  @IsOptional() @IsBoolean() active?: boolean;
}

export class CreateExpenseDto {
  @IsOptional() @IsString() supplier_id?: string;
  @IsString() @IsNotEmpty() category_id!: string;
  @IsString() @IsNotEmpty() description!: string;
  @IsInt() @Min(1) amount_cents!: number;
  @IsDateString() due_date!: string;
  @IsDateString() competence_date!: string;
  @IsOptional() @IsString() notes?: string;
}

export class UpdateExpenseDto {
  @IsOptional() @IsString() supplier_id?: string;
  @IsOptional() @IsString() category_id?: string;
  @IsOptional() @IsString() @IsNotEmpty() description?: string;
  @IsOptional() @IsInt() @Min(1) amount_cents?: number;
  @IsOptional() @IsDateString() due_date?: string;
  @IsOptional() @IsDateString() competence_date?: string;
  @IsOptional() @IsString() notes?: string;
}

export class CreateExpensePaymentDto {
  @IsInt() @Min(1) amount_cents!: number;
  @IsDateString() paid_at!: string;
  @IsOptional() @IsString() payment_method?: string;
  @IsOptional() @IsString() notes?: string;
}

export class CreateRecurringExpenseDto {
  @IsOptional() @IsString() supplier_id?: string;
  @IsString() @IsNotEmpty() category_id!: string;
  @IsString() @IsNotEmpty() description!: string;
  @IsInt() @Min(1) amount_cents!: number;
  @IsInt() @Min(1) @Max(31) due_day!: number;
  @IsDateString() start_date!: string;
  @IsOptional() @IsDateString() end_date?: string;
}

export class GenerateRecurringExpensesDto {
  @IsDateString() competence!: string;
}

export class PurchaseItemDto {
  @IsString() @IsNotEmpty() product_id!: string;
  @IsNumber({ maxDecimalPlaces: 3 }) @Min(0.001) quantity!: number;
  @IsInt() @Min(0) unit_cost_cents!: number;
}

export class CreatePurchaseDto {
  @IsOptional() @IsString() supplier_id?: string;
  @IsOptional() @IsString() document_no?: string;
  @IsDateString() purchased_at!: string;
  @IsOptional() @IsString() notes?: string;
  @IsArray() @ValidateNested({ each: true }) @Type(() => PurchaseItemDto)
  items!: PurchaseItemDto[];
  @IsOptional() @IsBoolean() create_payable?: boolean;
  @IsOptional() @IsString() expense_category_id?: string;
  @IsOptional() @IsDateString() due_date?: string;
}

export class AdjustStockDto {
  @IsNumber({ maxDecimalPlaces: 3 }) quantity!: number;
  @IsIn(['adjustment_in', 'adjustment_out', 'return']) type!: string;
  @IsOptional() @IsInt() @Min(0) unit_cost_cents?: number;
  @IsOptional() @IsString() notes?: string;
}

export class CreateEmployeeDto {
  @IsString() @IsNotEmpty() name!: string;
  @IsEmail() email!: string;
  @IsString() @IsNotEmpty() password!: string;
  @IsIn(['waiter', 'kitchen', 'cashier', 'manager']) role!: string;
}

export class UpdateEmployeeDto {
  @IsOptional() @IsString() @IsNotEmpty() name?: string;
  @IsOptional() @IsIn(['waiter', 'kitchen', 'cashier', 'manager']) role?: string;
  @IsOptional() @IsBoolean() active?: boolean;
  @IsOptional() @IsString() @IsNotEmpty() password?: string;
}

export class UpdatePrinterSettingDto {
  @IsOptional() @IsIn([58, 80]) paper_width?: number;
  @IsOptional() @IsString() printer_name?: string;
  @IsOptional() @IsIn(['system_spooler', 'esc_pos_bluetooth']) protocol?: string;
}

export class UpdateDiscountPolicyDto {
  @IsInt() @Min(0) @Max(10000) cashier_discount_limit_bps!: number;
}

export class CreatePixChargeDto {
  @IsString() @IsNotEmpty() order_id!: string;
  @IsOptional() @IsInt() @Min(1) expires_in_seconds?: number;
  @IsOptional() @IsIn(['fixed', 'percent']) discount_type?: string;
  @IsOptional() @IsInt() @Min(0) discount_value?: number;
  @IsOptional() @IsInt() @Min(0) discount_cents?: number;
  @IsOptional() @IsInt() @Min(0) service_fee_bps?: number;
  @IsOptional() @IsInt() @Min(1) expected_version?: number;
}

export class PixWebhookDto {
  @IsString() @IsNotEmpty() txid!: string;
  @IsIn(['paid', 'expired', 'canceled', 'failed']) status!: string;
  @IsOptional() @IsInt() @Min(1) amount_cents?: number;
  @IsOptional() @IsString() event_id?: string;
}
