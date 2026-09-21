import { Body, Controller, Get, Post, Request, UnauthorizedException, UseGuards } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from './prisma.service';
import { AuthGuard } from './auth.guard';

interface LoginBody {
  email?: unknown;
  password?: unknown;
}

interface AuthenticatedRequest {
  user: { sub: string };
}

@Controller('v1')
export class AppController {
  constructor(
    private readonly jwtService: JwtService,
    private readonly prisma: PrismaService,
  ) {}

  @Post('auth/login')
  async login(@Body() body: LoginBody) {
    if (typeof body.email !== 'string' || typeof body.password !== 'string') {
      throw new UnauthorizedException('E-mail ou senha inválidos.');
    }

    const user = await this.prisma.user.findUnique({ where: { email: body.email } });
    if (!user || user.password !== body.password) {
      throw new UnauthorizedException('E-mail ou senha inválidos.');
    }

    return {
      user: { id: user.id, name: user.name, email: user.email },
      access_token: await this.jwtService.signAsync({ sub: user.id, email: user.email }),
      refresh_token: 'fake-refresh-token',
    };
  }

  @UseGuards(AuthGuard)
  @Get('me/tenants')
  async getTenants(@Request() request: AuthenticatedRequest) {
    const tenants = await this.prisma.userTenant.findMany({
      where: { userId: request.user.sub },
      include: { tenant: true },
    });
    return {
      data: tenants.map(({ tenant, role }) => ({ ...tenant, role })),
    };
  }
}
