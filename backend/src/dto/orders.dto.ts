import { IsIn, IsInt, IsOptional, IsString, Length, Matches, Max, Min } from 'class-validator';

export class EmptyDto {}

export class CreateOrderDto {
  @IsString()
  @Length(1, 120)
  @Matches(/\S/)
  table_label!: string;
}

export class AddItemDto {
  @IsOptional()
  @IsString()
  @Length(1, 128)
  product_id?: string;

  @IsOptional()
  @IsString()
  @Length(1, 200)
  product_name?: string;

  @IsInt()
  @Min(1)
  @Max(10000)
  quantity!: number;

  @IsOptional()
  @IsString()
  @Length(0, 2000)
  notes?: string;
}

export class UpdateOrderStatusDto {
  @IsIn(['sentToKitchen', 'delivered'])
  status!: string;
}

export class OrdersQueryDto {
  @IsOptional()
  @IsString()
  @Length(0, 200)
  @Matches(/^\s*(?:(?:open|sentToKitchen|delivered|closed|canceled)\s*(?:,\s*(?:open|sentToKitchen|delivered|closed|canceled)\s*)*)?$/)
  status?: string;
}
