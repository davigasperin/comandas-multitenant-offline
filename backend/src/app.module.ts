import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { ThrottlerModule } from '@nestjs/throttler';
import { AppController } from './app.controller';
import { OrdersController } from './orders.controller';
import { OrdersGateway } from './orders.gateway';
import { PrismaModule } from './prisma.module';
import { AuthService } from './auth.service';
import { validateJwtSecret } from './config.utils';

import { CatalogController } from './catalog.controller';
import { EmployeesController, SettingsController } from './admin.controller';
import { FinanceController, InventoryController, PurchasesController, SuppliersController } from './management.controller';
import { ReportsController } from './reports.controller';
import { FeatureGuard } from './feature.guard';
import { PixController, PixWebhookController } from './pix.controller';
import { PixService } from './pix.service';

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
  controllers: [
    AppController,
    OrdersController,
    CatalogController,
    SuppliersController,
    FinanceController,
    InventoryController,
    PurchasesController,
    EmployeesController,
    SettingsController,
    ReportsController,
    PixController,
    PixWebhookController,
  ],
  providers: [AuthService, OrdersGateway, FeatureGuard, PixService],
})
export class AppModule {}
