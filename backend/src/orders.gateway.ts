import { JwtService } from '@nestjs/jwt';
import { ConnectedSocket, OnGatewayConnection, WebSocketGateway, WebSocketServer } from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { PrismaService } from './prisma.service';

@WebSocketGateway({ cors: true, namespace: '/orders' })
export class OrdersGateway implements OnGatewayConnection {
  @WebSocketServer()
  private server!: Server;

  constructor(
    private readonly jwtService: JwtService,
    private readonly prisma: PrismaService,
  ) {}

  async handleConnection(@ConnectedSocket() client: Socket): Promise<void> {
    try {
      const auth = client.handshake.auth ?? {};
      const token = auth.token;
      const tenantId = auth.tenantId;
      if (typeof token !== 'string' || typeof tenantId !== 'string' || !tenantId) throw new Error('Invalid handshake');
      const payload = await this.jwtService.verifyAsync<{ sub?: string; exp?: number }>(token);
      if (typeof payload.sub !== 'string' || !payload.sub.trim() || !Number.isFinite(payload.exp) || payload.exp! * 1000 <= Date.now()) throw new Error('Invalid token');
      const access = await this.prisma.userTenant.findUnique({
        where: { userId_tenantId: { userId: payload.sub, tenantId } },
      });
      if (!access) throw new Error('Tenant access denied');
      client.data.userId = payload.sub;
      client.data.tenantId = tenantId;
      await client.join(tenantId);
    } catch {
      client.disconnect(true);
    }
  }

  emitToTenant(tenantId: string, event: string, data: unknown): void {
    this.server.to(tenantId).emit(event, data);
  }
}
