import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'queued_mutation.dart';

class MutationQueueStorage {
  static const String queueStorageKey = 'durable_mutation_queue_v2';
  final SharedPreferences prefs;
  final _changes = StreamController<void>.broadcast();
  Future<void> _lock = Future.value();

  MutationQueueStorage(this.prefs) {
    _recoverState();
  }

  Stream<void> get changes => _changes.stream;

  void dispose() => _changes.close();

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _lock = _lock.then((_) async {
      try {
        final result = await action();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  void _recoverState() {
    final list = _readRaw();
    bool modified = false;
    for (int i = 0; i < list.length; i++) {
      if (list[i].status == MutationStatus.syncing) {
        list[i] = list[i].copyWith(status: MutationStatus.pending);
        modified = true;
      }
    }
    if (modified) {
      _writeRaw(list);
    }
  }

  List<QueuedMutation> _readRaw() {
    final raw = prefs.getStringList(queueStorageKey);
    if (raw == null || raw.isEmpty) return [];
    final results = <QueuedMutation>[];
    for (final item in raw) {
      try {
        final map = jsonDecode(item) as Map<String, dynamic>;
        results.add(QueuedMutation.fromJson(map));
      } catch (_) {
        // preserve corrupted representation if necessary or unparseable item
      }
    }
    return results;
  }

  Future<bool> _writeRaw(List<QueuedMutation> mutations) async {
    final raw = mutations.map((m) => jsonEncode(m.toJson())).toList();
    final ok = await prefs.setStringList(queueStorageKey, raw);
    if (!_changes.isClosed) _changes.add(null);
    return ok;
  }

  List<QueuedMutation> getAll() {
    return _readRaw();
  }

  Future<void> saveAll(List<QueuedMutation> mutations) {
    return _synchronized(() async {
      await _writeRaw(mutations);
    });
  }

  Future<void> enqueue(QueuedMutation mutation) {
    return _synchronized(() async {
      final list = _readRaw();
      if (list.any((m) => m.idempotencyKey == mutation.idempotencyKey)) {
        return;
      }
      list.add(mutation);
      await _writeRaw(list);
    });
  }

  List<QueuedMutation> getPendingFor(
      {required String tenantId, required String userId}) {
    return _readRaw()
        .where((m) =>
            m.tenantId == tenantId &&
            m.userId == userId &&
            (m.status == MutationStatus.pending ||
                m.status == MutationStatus.failed))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<void> updateStatus(
    String id,
    MutationStatus status, {
    String? lastError,
    int? retryCount,
    DateTime? nextAttemptAt,
    bool clearNextAttemptAt = false,
  }) {
    return _synchronized(() async {
      final list = _readRaw();
      final index = list.indexWhere((m) => m.id == id);
      if (index != -1) {
        final current = list[index];
        list[index] = current.copyWith(
          status: status,
          lastError: lastError ?? current.lastError,
          retryCount: retryCount ?? current.retryCount,
          nextAttemptAt: nextAttemptAt,
          clearNextAttemptAt: clearNextAttemptAt,
        );
        await _writeRaw(list);
      }
    });
  }

  Future<void> remapTempOrderId({
    required String oldTempId,
    required String realOrderId,
  }) {
    return _synchronized(() async {
      final list = _readRaw();
      bool modified = false;
      for (int i = 0; i < list.length; i++) {
        final m = list[i];
        String newPath = m.path;
        String? newDepends = m.dependsOnTempOrderId;
        if (m.path.contains(oldTempId)) {
          newPath = m.path.replaceAll(oldTempId, realOrderId);
          modified = true;
        }
        if (m.dependsOnTempOrderId == oldTempId) {
          newDepends = null;
          modified = true;
        }
        if (modified) {
          list[i] = m.copyWith(
            path: newPath,
            dependsOnTempOrderId: newDepends,
          );
        }
      }
      if (modified) {
        await _writeRaw(list);
      }
    });
  }

  Future<void> remove(String id) {
    return _synchronized(() async {
      final list = _readRaw();
      list.removeWhere((m) => m.id == id);
      await _writeRaw(list);
    });
  }

  Future<void> clear() {
    return _synchronized(() async {
      await prefs.remove(queueStorageKey);
      if (!_changes.isClosed) _changes.add(null);
    });
  }
}
