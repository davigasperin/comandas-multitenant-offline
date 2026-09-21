import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from './prisma.service';
import { generateRefreshToken, hashToken, verifyPassword } from './auth.utils';

const REFRESH_TOKEN_TTL_MS = 30 * 24 * 60 * 60 * 1000;

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwtService: JwtService,
  ) {}

  private unauthorized(): never {
    throw new UnauthorizedException('E-mail, senha ou sessão inválidos.');
  }

  private async issueSession(user: { id: string; name: string; email: string }) {
    const refreshToken = generateRefreshToken();
    await this.prisma.refreshToken.create({
      data: {
        tokenHash: hashToken(refreshToken),
        userId: user.id,
        expiresAt: new Date(Date.now() + REFRESH_TOKEN_TTL_MS),
      },
    });
    return {
      user: { id: user.id, name: user.name, email: user.email },
      access_token: await this.jwtService.signAsync({ sub: user.id, email: user.email }),
      refresh_token: refreshToken,
    };
  }

  async login(email: string, password: string) {
    const user = await this.prisma.user.findUnique({ where: { email: email.trim().toLowerCase() } });
    if (!user || !(await verifyPassword(password, user.password))) this.unauthorized();
    return this.issueSession(user);
  }

  async refresh(rawToken: string) {
    const tokenHash = hashToken(rawToken);
    const replacement = generateRefreshToken();
    const replacementHash = hashToken(replacement);

    const tokenRecord = await this.prisma.refreshToken.findUnique({
      where: { tokenHash },
      include: { user: true },
    });

    if (!tokenRecord || tokenRecord.expiresAt <= new Date()) {
      this.unauthorized();
    }

    if (tokenRecord.revokedAt) {
      await this.prisma.refreshToken.updateMany({
        where: { userId: tokenRecord.userId, revokedAt: null },
        data: { revokedAt: new Date() },
      });
      this.unauthorized();
    }

    return this.prisma.$transaction(async (tx) => {
      const claimed = await tx.refreshToken.updateMany({
        where: { id: tokenRecord.id, revokedAt: null },
        data: { revokedAt: new Date(), replacedBy: replacementHash },
      });

      if (claimed.count !== 1) {
        await tx.refreshToken.updateMany({
          where: { userId: tokenRecord.userId, revokedAt: null },
          data: { revokedAt: new Date() },
        });
        this.unauthorized();
      }

      await tx.refreshToken.create({
        data: {
          tokenHash: replacementHash,
          userId: tokenRecord.userId,
          expiresAt: new Date(Date.now() + REFRESH_TOKEN_TTL_MS),
        },
      });

      return {
        user: { id: tokenRecord.user.id, name: tokenRecord.user.name, email: tokenRecord.user.email },
        access_token: await this.jwtService.signAsync({ sub: tokenRecord.user.id, email: tokenRecord.user.email }),
        refresh_token: replacement,
      };
    });
  }

  async logout(rawToken: string): Promise<void> {
    const tokenHash = hashToken(rawToken);
    const tokenRecord = await this.prisma.refreshToken.findUnique({
      where: { tokenHash },
    });
    if (!tokenRecord) return;

    await this.prisma.refreshToken.updateMany({
      where: { userId: tokenRecord.userId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }
}
