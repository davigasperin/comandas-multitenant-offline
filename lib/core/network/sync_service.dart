import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'offline_interceptor.dart';

class SyncService {
  final Dio dio;
  final SharedPreferences prefs;
  final FlutterSecureStorage storage;
  String? lastError;

  SyncService(this.dio, this.prefs, this.storage);

  bool get isSyncing => false;
  int get pendingCount => 0;

  Future<int> sync() async {
    lastError = (prefs.getStringList(OfflineInterceptor.queueKey) ?? []).isNotEmpty
        ? 'Fila antiga preservada. Proprietário não verificável; envio bloqueado.'
        : 'Envio offline indisponível: armazenamento durável ainda não implementado.';
    return 0;
  }
}
