import 'package:comandas_app/core/network/mutation_queue_storage.dart';
import 'package:comandas_app/core/network/queued_mutation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MutationQueueStorage enqueues, retrieves FIFO, and updates status', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = MutationQueueStorage(prefs);

    final m1 = QueuedMutation(
      id: 'm1',
      idempotencyKey: 'key_1',
      method: 'POST',
      path: '/orders',
      body: const {'table_label': 'Mesa 1'},
      tenantId: 'ten_1',
      userId: 'usr_1',
      createdAt: DateTime.now().subtract(const Duration(seconds: 10)),
    );

    final m2 = QueuedMutation(
      id: 'm2',
      idempotencyKey: 'key_2',
      method: 'POST',
      path: '/orders',
      body: const {'table_label': 'Mesa 2'},
      tenantId: 'ten_1',
      userId: 'usr_1',
      createdAt: DateTime.now(),
    );

    await storage.enqueue(m1);
    await storage.enqueue(m2);

    final pending = storage.getPendingFor(tenantId: 'ten_1', userId: 'usr_1');
    expect(pending.length, 2);
    expect(pending[0].id, 'm1');
    expect(pending[1].id, 'm2');

    await storage.updateStatus('m1', MutationStatus.syncing);
    expect(storage.getPendingFor(tenantId: 'ten_1', userId: 'usr_1').length, 1);

    await storage.remove('m1');
    final pendingAfterRemove = storage.getPendingFor(tenantId: 'ten_1', userId: 'usr_1');
    expect(pendingAfterRemove.length, 1);
    expect(pendingAfterRemove[0].id, 'm2');
  });
}
