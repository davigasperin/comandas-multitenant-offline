import { IsArray, IsBoolean, IsIn, IsInt, IsNotEmpty, IsNumber, IsOptional, IsString, Max, Min, ValidateIf, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';

export class CreateOrderDto {
  @IsOptional()
  @IsString()
  table_label?: string;

  @IsOptional()
  @IsIn(['table', 'quick_sale', 'takeaway', 'delivery'])
  order_type?: string;

  @IsOptional()
  @IsString()
  table_id?: string;
}

export class AddItemDto {
  @IsOptional()
  @IsString()
  product_id?: string;

  @IsOptional()
  @IsString()
  product_name?: string;

  @IsInt({ message: 'quantity deve ser um número inteiro' })
  @Min(1, { message: 'quantity deve ser maior que zero' })
  quantity!: number;

  @IsOptional()
  @IsInt({ message: 'unit_price_cents deve ser um número inteiro em centavos' })
  @Min(0, { message: 'unit_price_cents não pode ser negativo' })
  unit_price_cents?: number;

  @IsOptional()
  @IsString()
  notes?: string;

  @IsOptional()
  @IsString()
  selected_options?: string;

  @IsOptional()
  @IsInt({ message: 'expected_version deve ser um número inteiro' })
  @Min(1)
  expected_version?: number;
}

export class UpdateOrderStatusDto {
  @IsString()
  @IsNotEmpty({ message: 'status é obrigatório' })
  status!: string;

  @IsOptional()
  @IsInt({ message: 'expected_version deve ser um número inteiro' })
  @Min(1)
  expected_version?: number;
}

export class OrderPaymentDto {
  @IsString()
  @IsNotEmpty()
  method!: string; // cash, pix, credit, debit, voucher

  @IsInt()
  @Min(1)
  amount_cents!: number;

  @IsOptional()
  @IsInt()
  @Min(0)
  tendered_cents?: number;
}

export class SettleOrderDto {
  @IsOptional()
  @IsInt()
  @Min(0)
  discount_cents?: number;

  @IsOptional()
  @IsIn(['fixed', 'percent'])
  discount_type?: string;

  @ValidateIf((body: SettleOrderDto) => body.discount_type !== undefined)
  @IsInt()
  @Min(0)
  discount_value?: number;

  @IsOptional()
  @IsInt()
  @Min(0)
  service_fee_bps?: number;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => OrderPaymentDto)
  payments!: OrderPaymentDto[];

  @IsOptional()
  @IsInt()
  @Min(1)
  expected_version?: number;
}

export class CloseOrderDto {
  @IsOptional()
  @IsInt()
  @Min(1)
  expected_version?: number;

  @IsOptional()
  @IsInt()
  @Min(0)
  discount_cents?: number;

  @IsOptional()
  @IsIn(['fixed', 'percent'])
  discount_type?: string;

  @ValidateIf((body: CloseOrderDto) => body.discount_type !== undefined)
  @IsInt()
  @Min(0)
  discount_value?: number;

  @IsOptional()
  @IsInt()
  @Min(0)
  service_fee_bps?: number;

  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => OrderPaymentDto)
  payments?: OrderPaymentDto[];
}

export class QueryOrdersDto {
  @IsOptional()
  @IsString()
  status?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;

  @IsOptional()
  @IsString()
  cursor?: string;
}

export class CreateCategoryDto {
  @IsString()
  @IsNotEmpty()
  name!: string;

  @IsOptional()
  @IsInt()
  sort_order?: number;

  @IsOptional()
  @IsBoolean()
  active?: boolean;

  @IsOptional()
  @IsIn(['kitchen', 'bar', 'dessert', 'none'])
  production_area?: string;

}

export class UpdateCategoryDto {
  @IsOptional()
  @IsString()
  name?: string;

  @IsOptional()
  @IsInt()
  sort_order?: number;

  @IsOptional()
  @IsBoolean()
  active?: boolean;

  @IsOptional()
  @IsIn(['kitchen', 'bar', 'dessert', 'none'])
  production_area?: string;
}

export class CreateProductDto {
  @IsString()
  @IsNotEmpty()
  name!: string;

  @IsInt()
  @Min(0)
  price_cents!: number;

  @IsOptional()
  @IsInt()
  @Min(0)
  cost_cents?: number;

  @IsOptional()
  @IsString()
  sku?: string;

  @IsOptional()
  @IsIn(['unit', 'kg', 'g', 'l', 'ml', 'portion'])
  unit?: string;

  @IsOptional()
  @IsBoolean()
  stock_controlled?: boolean;

  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 3 })
  minimum_stock?: number;

  @IsOptional()
  @IsString()
  category_id?: string;

  @IsOptional()
  @IsBoolean()
  active?: boolean;

  @IsOptional()
  @IsBoolean()
  available?: boolean;

  @IsOptional()
  @IsInt()
  sort_order?: number;
}

export class UpdateProductDto {
  @IsOptional()
  @IsString()
  name?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  price_cents?: number;

  @IsOptional()
  @IsInt()
  @Min(0)
  cost_cents?: number;

  @IsOptional()
  @IsString()
  sku?: string;

  @IsOptional()
  @IsIn(['unit', 'kg', 'g', 'l', 'ml', 'portion'])
  unit?: string;

  @IsOptional()
  @IsBoolean()
  stock_controlled?: boolean;

  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 3 })
  minimum_stock?: number;

  @IsOptional()
  @IsString()
  category_id?: string;

  @IsOptional()
  @IsBoolean()
  active?: boolean;

  @IsOptional()
  @IsBoolean()
  available?: boolean;

  @IsOptional()
  @IsInt()
  sort_order?: number;
}

export class CreateTableDto {
  @IsString()
  @IsNotEmpty()
  label!: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(100)
  capacity?: number;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(5000)
  pos_x?: number;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(5000)
  pos_y?: number;

  @IsOptional()
  @IsInt()
  @Min(40)
  @Max(800)
  width?: number;

  @IsOptional()
  @IsInt()
  @Min(40)
  @Max(800)
  height?: number;

  @IsOptional()
  @IsIn(['square', 'rectangle', 'circle'])
  shape?: string;
}

export class UpdateTableDto {
  @IsOptional()
  @IsString()
  label?: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(100)
  capacity?: number;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(5000)
  pos_x?: number;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(5000)
  pos_y?: number;

  @IsOptional()
  @IsInt()
  @Min(40)
  @Max(800)
  width?: number;

  @IsOptional()
  @IsInt()
  @Min(40)
  @Max(800)
  height?: number;

  @IsOptional()
  @IsIn(['square', 'rectangle', 'circle'])
  shape?: string;

  @IsOptional()
  @IsBoolean()
  active?: boolean;
}

export class UpdateTableLayoutDto {
  @IsInt()
  @Min(0)
  @Max(5000)
  pos_x!: number;

  @IsInt()
  @Min(0)
  @Max(5000)
  pos_y!: number;

  @IsOptional()
  @IsInt()
  @Min(40)
  @Max(800)
  width?: number;

  @IsOptional()
  @IsInt()
  @Min(40)
  @Max(800)
  height?: number;

  @IsOptional()
  @IsIn(['square', 'rectangle', 'circle'])
  shape?: string;
}

export class TransferTableDto {
  @IsString()
  @IsNotEmpty()
  target_table_id!: string;
}
