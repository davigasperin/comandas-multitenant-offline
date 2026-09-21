import 'package:comandas_app/core/constants/app_constants.dart';
import 'package:comandas_app/core/network/auth_tenant_interceptor.dart';
import 'package:comandas_app/core/network/mutation_queue_storage.dart';
import 'package:comandas_app/core/network/offline_interceptor.dart';
import 'package:comandas_app/core/network/sync_service.dart';
import 'package:comandas_app/features/orders/data/orders_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks/fake_http_client_adapter.dart';
import '../mocks/fake_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('offline create, item, close, restart and replay use real order id',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = FakeSecureStorage();
    await storage.write(
        key: AppConstants.storageKeyAccessToken, value: 'tok_e2e');
    await storage.write(
        key: AppConstants.storageKeySelectedTenantId, value: 'ten_e2e');
    await storage.write(key: AppConstants.storageKeyUserId, value: 'usr_e2e');

    final queue = MutationQueueStorage(prefs);
    final dio = Dio();
    dio.interceptors.add(AuthTenantInterceptor(storage, dio));
    dio.interceptors.add(OfflineInterceptor(prefs, queue));
    var online = false;
    final replayed = <RequestOptions>[];
    dio.httpClientAdapter = FakeHttpClientAdapter((options) async {
      if (!online) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
      replayed.add(options);
      if (options.path == '/orders') {
        return FakeHttpClientAdapter.json(
            {'id': 'order_real_999', 'table_label': 'Mesa 12'}, 201);
      }
      return FakeHttpClientAdapter.json({'status': 'closed'}, 200);
    });

    final repository = OrdersRepository(dio);
    final order = await repository.createOrder(tableLabel: 'Mesa 12');
    await repository.addItem(
        orderId: order.id, productId: 'product_1', quantity: 2);
    expect(await repository.closeOrder(order.id), isFalse);
    expect(order.id, startsWith('temp_'));
    expect(queue.getPendingFor(tenantId: 'ten_e2e', userId: 'usr_e2e'),
        hasLength(3));

    final recreatedQueue = MutationQueueStorage(prefs);
    online = true;
    final synced =
        await SyncService(dio, prefs, storage, recreatedQueue).sync();

    expect(synced, 3);
    expect(recreatedQueue.getPendingFor(tenantId: 'ten_e2e', userId: 'usr_e2e'),
        isEmpty);
    expect(replayed.map((request) => request.path), [
      '/orders',
      '/orders/order_real_999/items',
      '/orders/order_real_999/close',
    ]);
    expect(replayed.map((request) => request.headers['X-Idempotency-Key']),
        everyElement(isNotEmpty));
  });
}
