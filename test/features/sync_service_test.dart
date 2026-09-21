import 'package:comandas_app/core/constants/app_constants.dart';
import 'package:comandas_app/core/network/mutation_queue_storage.dart';
import 'package:comandas_app/core/network/queued_mutation.dart';
import 'package:comandas_app/core/network/sync_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks/fake_http_client_adapter.dart';
import '../mocks/fake_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SyncService replays pending mutations FIFO and clears queue on success', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final queue = MutationQueueStorage(prefs);
    final storage = FakeSecureStorage();

    await storage.write(key: AppConstants.storageKeySelectedTenantId, value: 'ten_test');
    await storage.write(key: AppConstants.storageKeyUserId, value: 'usr_test');

    final mutation1 = QueuedMutation(
      id: 'mut_1',
      idempotencyKey: 'idemp_1',
      method: 'POST',
      path: '/orders',
      body: {'table_label': 'Mesa 10'},
      tenantId: 'ten_test',
      userId: 'usr_test',
      createdAt: DateTime.now().subtract(const Duration(seconds: 5)),
    );

    final mutation2 = QueuedMutation(
      id: 'mut_2',
      idempotencyKey: 'idemp_2',
      method: 'POST',
      path: '/orders/ord_10/items',
      body: {'product_name': 'Suco', 'quantity': 2},
      tenantId: 'ten_test',
      userId: 'usr_test',
      createdAt: DateTime.now(),
    );

    await queue.enqueue(mutation1);
    await queue.enqueue(mutation2);

    final sentRequests = <RequestOptions>[];
    final dio = Dio();
    dio.httpClientAdapter = FakeHttpClientAdapter((options) async {
      sentRequests.add(options);
      return ResponseBody.fromString('{"ok": true}', 201);
    });

    final syncService = SyncService(dio, prefs, storage, queue);
    expect(syncService.pendingCount, 2);

    final count = await syncService.sync();
    expect(count, 2);
    expect(syncService.pendingCount, 0);
    expect(sentRequests.length, 2);
    expect(sentRequests[0].headers['X-Idempotency-Key'], 'idemp_1');
    expect(sentRequests[1].headers['X-Idempotency-Key'], 'idemp_2');
  });
}
