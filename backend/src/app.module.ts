import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { ThrottlerModule } from '@nestjs/throttler';
import { AppController } from './app.controller';
import { OrdersController } from './orders.controller';
import { OrdersGateway } from './orders.gateway';
import { PrismaModule } from './prisma.module';
import { AuthService } from './auth.service';
import { validateJwtSecret } from './config.utils';

@Module({
  imports: [
    PrismaModule,
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: 100 }]),
    JwtModule.register({
      global: true,
      secret: validateJwtSecret(process.env.JWT_SECRET),
      signOptions: { expiresIn: '15m' },
    }),
  ],
  controllers: [AppController, OrdersController],
  providers: [AuthService, OrdersGateway],
})
export class AppModule {}
