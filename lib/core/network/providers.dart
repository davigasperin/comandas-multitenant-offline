import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mutation_queue_storage.dart';
import 'offline_interceptor.dart';
import 'sync_service.dart';
import 'socket_service.dart';

import 'api_client.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/tenant/data/tenant_repository.dart';
import '../../features/orders/data/orders_repository.dart';
import '../../features/orders/data/receipt_service.dart';

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final mutationQueueStorageProvider = Provider<MutationQueueStorage>((ref) {
  final storage = MutationQueueStorage(ref.watch(sharedPreferencesProvider));
  ref.onDispose(storage.dispose);
  return storage;
});

final offlineInterceptorProvider = Provider<OfflineInterceptor>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return OfflineInterceptor(prefs, ref.watch(mutationQueueStorageProvider));
});

final dioProvider = Provider<Dio>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final offline = ref.watch(offlineInterceptorProvider);
  return ApiClient(storage, offline).dio;
});

final syncServiceProvider = Provider<SyncService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final storage = ref.watch(secureStorageProvider);
  final queue = ref.watch(mutationQueueStorageProvider);
  final service = SyncService(ref.watch(dioProvider), prefs, storage, queue);
  ref.onDispose(() => service.dispose());
  return service;
});

final currentUserIdProvider = FutureProvider<String?>((ref) async {
  final storage = ref.watch(secureStorageProvider);
  return storage.read(key: 'user_id');
});

final currentTenantIdProvider = FutureProvider<String?>((ref) async {
  final storage = ref.watch(secureStorageProvider);
  return storage.read(key: 'selected_tenant_id');
});

final pendingMutationCountProvider = StreamProvider<int>((ref) async* {
  final storage = ref.watch(mutationQueueStorageProvider);
  final secureStorage = ref.watch(secureStorageProvider);

  Future<int> computeScopedCount() async {
    final tenantId = await secureStorage.read(key: 'selected_tenant_id');
    final userId = await secureStorage.read(key: 'user_id');
    if (tenantId == null || userId == null) return 0;
    return storage.getPendingFor(tenantId: tenantId, userId: userId).length;
  }

  yield await computeScopedCount();
  await for (final _ in storage.changes) {
    yield await computeScopedCount();
  }
});

final socketServiceProvider = Provider<SocketService>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final service = SocketService(storage);
  ref.onDispose(() => service.dispose());
  return service;
});

final socketConnectionStateProvider =
    StreamProvider.autoDispose<SocketConnectionState>((ref) {
  final socketService = ref.watch(socketServiceProvider);
  return socketService.connectionStateStream;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
      ref.watch(dioProvider), ref.watch(secureStorageProvider));
});

final tenantRepositoryProvider = Provider<TenantRepository>((ref) {
  return TenantRepository(
      ref.watch(dioProvider), ref.watch(secureStorageProvider));
});

final ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  return OrdersRepository(ref.watch(dioProvider));
});

final receiptServiceProvider = Provider<ReceiptService>((ref) {
  return StandardReceiptService(ref.watch(tenantRepositoryProvider));
});
