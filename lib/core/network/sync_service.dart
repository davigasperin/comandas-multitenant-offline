import 'dart:async';
import 'dart:math';
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

  Future<int> getScopedPendingCount() async {
    final tenantId =
        await storage.read(key: AppConstants.storageKeySelectedTenantId);
    final userId = await storage.read(key: AppConstants.storageKeyUserId);
    if (tenantId == null || userId == null) return 0;
    return queue.getPendingFor(tenantId: tenantId, userId: userId).length;
  }

  int get pendingCount {
    return queue
        .getAll()
        .where((m) =>
            m.status == MutationStatus.pending ||
            m.status == MutationStatus.failed)
        .length;
  }

  Future<int> sync() async {
    if (_isSyncing) return 0;
    final tenantId =
        await storage.read(key: AppConstants.storageKeySelectedTenantId);
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
    final now = DateTime.now();

    try {
      final activeTempOrders = <String, String>{};

      for (final mutation in pending) {
        if (mutation.nextAttemptAt != null &&
            now.isBefore(mutation.nextAttemptAt!)) {
          continue;
        }

        if (mutation.dependsOnTempOrderId != null) {
          final parentTemp = mutation.dependsOnTempOrderId!;
          if (!activeTempOrders.containsKey(parentTemp)) {
            final allItems = queue.getAll();
            final parentMutation = allItems.cast<QueuedMutation?>().firstWhere(
                  (m) => m?.tempOrderId == parentTemp,
                  orElse: () => null,
                );
            if (parentMutation != null &&
                parentMutation.status == MutationStatus.failed &&
                parentMutation.retryCount >= 5) {
              await queue.updateStatus(mutation.id, MutationStatus.failed,
                  lastError: 'Dependência pai falhou permanentemente.');
            }
            continue;
          }
        }

        await queue.updateStatus(mutation.id, MutationStatus.syncing);

        try {
          String requestPath = mutation.path;
          if (mutation.dependsOnTempOrderId != null &&
              activeTempOrders.containsKey(mutation.dependsOnTempOrderId)) {
            requestPath = requestPath.replaceAll(mutation.dependsOnTempOrderId!,
                activeTempOrders[mutation.dependsOnTempOrderId]!);
          }

          final response = await dio.request<dynamic>(
            requestPath,
            data: mutation.body,
            options: Options(
              method: mutation.method,
              headers: {
                'X-Idempotency-Key': mutation.idempotencyKey,
                'X-Tenant-Id': mutation.tenantId,
              },
              extra: {
                'skipOfflineQueue': true,
                'offlineReplay': true,
                'expectedOwner': mutation.userId,
              },
            ),
          );

          final statusCode = response.statusCode ?? 0;
          if (statusCode >= 200 && statusCode < 300) {
            if (mutation.tempOrderId != null && response.data is Map) {
              final respMap = response.data as Map;
              final realId = respMap['id']?.toString() ??
                  respMap['order']?['id']?.toString();
              if (realId != null) {
                activeTempOrders[mutation.tempOrderId!] = realId;
                await queue.remapTempOrderId(
                    oldTempId: mutation.tempOrderId!, realOrderId: realId);
              }
            }
            await queue.remove(mutation.id);
            syncedCount++;
          } else if (statusCode == 409) {
            // Conflict / idempotency duplicate -> safe to treat as delivered/acknowledged
            await queue.remove(mutation.id);
            syncedCount++;
          } else {
            final nextRetry = mutation.retryCount + 1;
            if (nextRetry >= 5) {
              await queue.updateStatus(
                mutation.id,
                MutationStatus.failed,
                lastError:
                    'Falha permanente após $nextRetry tentativas (Status $statusCode)',
                retryCount: nextRetry,
              );
            } else {
              final delaySeconds = min(30, pow(2, nextRetry).toInt());
              await queue.updateStatus(
                mutation.id,
                MutationStatus.pending,
                lastError: 'Status $statusCode',
                retryCount: nextRetry,
                nextAttemptAt:
                    DateTime.now().add(Duration(seconds: delaySeconds)),
              );
            }
          }
        } on DioException catch (e) {
          final statusCode = e.response?.statusCode;
          if (statusCode == 400 || statusCode == 404 || statusCode == 422) {
            // Client error -> permanent fail
            await queue.updateStatus(
              mutation.id,
              MutationStatus.failed,
              lastError: e.response?.data?.toString() ?? e.message,
              retryCount: mutation.retryCount + 1,
            );
          } else if (statusCode == 409) {
            await queue.remove(mutation.id);
            syncedCount++;
          } else {
            final nextRetry = mutation.retryCount + 1;
            if (nextRetry >= 5) {
              await queue.updateStatus(
                mutation.id,
                MutationStatus.failed,
                lastError:
                    'Falha permanente de rede após $nextRetry tentativas.',
                retryCount: nextRetry,
              );
            } else {
              final delaySeconds = min(30, pow(2, nextRetry).toInt());
              await queue.updateStatus(
                mutation.id,
                MutationStatus.pending,
                lastError: e.message ?? 'Erro de rede',
                retryCount: nextRetry,
                nextAttemptAt:
                    DateTime.now().add(Duration(seconds: delaySeconds)),
              );
              lastError = 'Conexão interrompida durante a sincronização.';
              break;
            }
          }
        } catch (e) {
          await queue.updateStatus(mutation.id, MutationStatus.failed,
              lastError: e.toString());
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
