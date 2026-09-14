import { Body, Controller, Get, Post, Request, UnauthorizedException, UseGuards } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { USERS, TENANTS, USER_TENANTS } from './db';
import { AuthGuard } from './auth.guard';

@Controller('v1')
export class AppController {
  constructor(private jwtService: JwtService) {}

  @Post('auth/login')
  async login(@Body() body: any) {
    const { email, password } = body;
    const user = USERS.find((u) => u.email === email && u.password === password);
    if (!user) throw new UnauthorizedException('E-mail ou senha inválidos.');

    const payload = { sub: user.id, email: user.email };
    const accessToken = await this.jwtService.signAsync(payload);
    
    return {
      user: { id: user.id, name: user.name, email: user.email },
      access_token: accessToken,
      refresh_token: 'fake-refresh-token',
    };
  }

  @UseGuards(AuthGuard)
  @Get('me/tenants')
  getTenants(@Request() req: any) {
    const userTenants = USER_TENANTS.filter((ut) => ut.userId === req.user.sub);
    const tenants = userTenants.map((ut) => {
      const t = TENANTS.find((t) => t.id === ut.tenantId);
      return { ...t, role: ut.role };
    });
    return { data: tenants };
  }
}
