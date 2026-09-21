import { IsInt, IsNotEmpty, IsOptional, IsString, Min } from 'class-validator';

export class CreateOrderDto {
  @IsString()
  @IsNotEmpty({ message: 'table_label é obrigatório' })
  table_label!: string;
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

export class CloseOrderDto {
  @IsOptional()
  @IsInt({ message: 'expected_version deve ser um número inteiro' })
  @Min(1)
  expected_version?: number;
}

export class QueryOrdersDto {
  @IsOptional()
  @IsString()
  status?: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  limit?: number;

  @IsOptional()
  @IsString()
  cursor?: string;
}
