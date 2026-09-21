import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AppController } from './app.controller';
import { OrdersController } from './orders.controller';
import { OrdersGateway } from './orders.gateway';
import { PrismaModule } from './prisma.module';

@Module({
  imports: [
    PrismaModule,
    JwtModule.register({
      global: true,
      secret: 'super-secret-jwt-key',
      signOptions: { expiresIn: '1d' },
    }),
  ],
  controllers: [AppController, OrdersController],
  providers: [OrdersGateway],
})
export class AppModule {}
