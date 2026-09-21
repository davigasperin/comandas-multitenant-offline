import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'queued_mutation.dart';

class MutationQueueStorage {
  static const String queueStorageKey = 'durable_mutation_queue_v1';
  final SharedPreferences prefs;
  final _changes = StreamController<void>.broadcast();

  MutationQueueStorage(this.prefs);

  Stream<void> get changes => _changes.stream;

  void dispose() => _changes.close();

  List<QueuedMutation> getAll() {
    final raw = prefs.getStringList(queueStorageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return raw.map((item) => QueuedMutation.fromJson(jsonDecode(item) as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAll(List<QueuedMutation> mutations) async {
    final raw = mutations.map((m) => jsonEncode(m.toJson())).toList();
    await prefs.setStringList(queueStorageKey, raw);
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> enqueue(QueuedMutation mutation) async {
    final list = getAll();
    list.add(mutation);
    await saveAll(list);
  }

  List<QueuedMutation> getPendingFor({required String tenantId, required String userId}) {
    return getAll()
        .where((m) => m.tenantId == tenantId && m.userId == userId && (m.status == MutationStatus.pending || m.status == MutationStatus.failed))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<void> updateStatus(String id, MutationStatus status, {String? lastError, int? retryCount}) async {
    final list = getAll();
    final index = list.indexWhere((m) => m.id == id);
    if (index != -1) {
      final current = list[index];
      list[index] = current.copyWith(
        status: status,
        lastError: lastError ?? current.lastError,
        retryCount: retryCount ?? current.retryCount,
      );
      await saveAll(list);
    }
  }

  Future<void> remove(String id) async {
    final list = getAll();
    list.removeWhere((m) => m.id == id);
    await saveAll(list);
  }

  Future<void> clear() async {
    await prefs.remove(queueStorageKey);
  }
}
