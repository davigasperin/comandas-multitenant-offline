import 'dotenv/config';
import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { getCorsOptions } from './config.utils';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { cors: getCorsOptions(process.env.CORS_ORIGINS) });
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }));
  await app.listen(Number(process.env.PORT ?? 3000));
}
bootstrap();
