import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';
import 'auth_tenant_interceptor.dart';
import 'offline_interceptor.dart';

class ApiClient {
  final Dio dio;

  ApiClient._(this.dio);

  factory ApiClient(
    FlutterSecureStorage storage,
    OfflineInterceptor offlineInterceptor,
  ) {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    dio.interceptors.add(AuthTenantInterceptor(storage, dio));
    dio.interceptors.add(offlineInterceptor);

    return ApiClient._(dio);
  }
}
