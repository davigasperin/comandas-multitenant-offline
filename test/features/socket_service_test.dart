import 'package:flutter_test/flutter_test.dart';
import 'package:comandas_app/core/network/socket_service.dart';
import '../mocks/fake_secure_storage.dart';

void main() {
  test('SocketService disconnects without credentials', () async {
    final storage = FakeSecureStorage();
    final service = SocketService(storage, url: 'http://localhost:9999/orders');

    final states = <SocketConnectionState>[];
    final sub = service.connectionStateStream.listen(states.add);

    await service.connect();

    await Future.delayed(const Duration(milliseconds: 50));
    expect(states.last, SocketConnectionState.disconnected);

    service.dispose();
    await sub.cancel();
  });

  test('SocketService dispose completes cleanly', () async {
    final storage = FakeSecureStorage();
    await storage.write(key: 'access_token', value: 'tok');
    await storage.write(key: 'selected_tenant_id', value: 'ten_1');

    final service = SocketService(storage, url: 'http://localhost:9999/orders');
    service.dispose();

    expect(service.currentState, SocketConnectionState.disconnected);
  });
}
