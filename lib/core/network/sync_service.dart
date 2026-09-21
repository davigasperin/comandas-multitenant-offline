import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import 'mutation_queue_storage.dart';
import 'queued_mutation.dart';

class SyncService {
  final Dio dio;
  final SharedPreferences prefs;
  final FlutterSecureStorage storage;
  final MutationQueueStorage queue;

  bool _isSyncing = false;
  String? lastError;
  final _pendingCountController = StreamController<int>.broadcast();

  SyncService(this.dio, this.prefs, this.storage, this.queue);

  bool get isSyncing => _isSyncing;
  Stream<int> get pendingCountStream => _pendingCountController.stream;

  int get pendingCount {
    return queue.getAll().where((m) => m.status == MutationStatus.pending || m.status == MutationStatus.failed).length;
  }

  Future<int> sync() async {
    if (_isSyncing) return 0;
    final tenantId = await storage.read(key: AppConstants.storageKeySelectedTenantId);
    final userId = await storage.read(key: AppConstants.storageKeyUserId);
    if (tenantId == null || userId == null) {
      lastError = 'Sessão ou tenant não identificados para sincronização.';
      return 0;
    }

    final pending = queue.getPendingFor(tenantId: tenantId, userId: userId);
    if (pending.isEmpty) {
      lastError = null;
      return 0;
    }

    _isSyncing = true;
    int syncedCount = 0;
    lastError = null;

    try {
      for (final mutation in pending) {
        await queue.updateStatus(mutation.id, MutationStatus.syncing);

        try {
          final response = await dio.request<dynamic>(
            mutation.path,
            data: mutation.body,
            options: Options(
              method: mutation.method,
              headers: {
                'X-Idempotency-Key': mutation.idempotencyKey,
                'X-Tenant-Id': mutation.tenantId,
              },
              extra: {'skipOfflineQueue': true},
            ),
          );

          final statusCode = response.statusCode ?? 0;
          if (statusCode >= 200 && statusCode < 300) {
            await queue.remove(mutation.id);
            syncedCount++;
          } else {
            await queue.updateStatus(mutation.id, MutationStatus.failed, lastError: 'Status $statusCode');
          }
        } on DioException catch (e) {
          final statusCode = e.response?.statusCode;
          if (statusCode == 400 || statusCode == 409 || statusCode == 404 || statusCode == 422) {
            await queue.updateStatus(
              mutation.id,
              MutationStatus.failed,
              lastError: e.response?.data?.toString() ?? e.message,
              retryCount: mutation.retryCount + 1,
            );
          } else {
            await queue.updateStatus(
              mutation.id,
              MutationStatus.pending,
              lastError: e.message ?? 'Erro de rede',
              retryCount: mutation.retryCount + 1,
            );
            lastError = 'Conexão interrompida durante a sincronização.';
            break;
          }
        } catch (e) {
          await queue.updateStatus(mutation.id, MutationStatus.failed, lastError: e.toString());
        }
      }
    } finally {
      _isSyncing = false;
      _pendingCountController.add(pendingCount);
    }

    return syncedCount;
  }

  void dispose() {
    _pendingCountController.close();
  }
}
