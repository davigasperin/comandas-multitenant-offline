import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AppController } from './app.controller';
import { OrdersController } from './orders.controller';

@Module({
  imports: [
    JwtModule.register({
      global: true,
      secret: 'super-secret-jwt-key',
      signOptions: { expiresIn: '1d' },
    }),
  ],
  controllers: [AppController, OrdersController],
})
export class AppModule {}
