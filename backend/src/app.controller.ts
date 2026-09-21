import { Body, Controller, Get, Post, Request, UseGuards } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { AuthGuard } from './auth.guard';
import { AuthService } from './auth.service';
import { LoginDto, RefreshTokenDto } from './dto/auth.dto';
import { PrismaService } from './prisma.service';

interface AuthenticatedRequest {
  user: { sub: string };
}

@Controller('v1')
export class AppController {
  constructor(
    private readonly authService: AuthService,
    private readonly prisma: PrismaService,
  ) {}

  @Throttle({ default: { limit: 5, ttl: 60_000, blockDuration: 60_000 } })
  @Post('auth/login')
  login(@Body() body: LoginDto) {
    return this.authService.login(body.email, body.password);
  }

  @Throttle({ default: { limit: 10, ttl: 60_000, blockDuration: 60_000 } })
  @Post('auth/refresh')
  refresh(@Body() body: RefreshTokenDto) {
    return this.authService.refresh(body.refresh_token);
  }

  @Post('auth/logout')
  async logout(@Body() body: RefreshTokenDto) {
    await this.authService.logout(body.refresh_token);
    return { ok: true };
  }

  @UseGuards(AuthGuard)
  @Get('me/tenants')
  async getTenants(@Request() request: AuthenticatedRequest) {
    const tenants = await this.prisma.userTenant.findMany({
      where: { userId: request.user.sub },
      include: { tenant: true },
    });
    return { data: tenants.map(({ tenant, role }) => ({ ...tenant, role })) };
  }
}
