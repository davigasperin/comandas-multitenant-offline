import { IsEmail, IsString, Length, Matches } from 'class-validator';

export class LoginDto {
  @IsEmail()
  @Length(3, 254)
  email!: string;

  @IsString()
  @Length(1, 1024)
  password!: string;
}

export class RefreshTokenDto {
  @IsString()
  @Matches(/^[A-Za-z0-9_-]{64}$/)
  refresh_token!: string;
}
