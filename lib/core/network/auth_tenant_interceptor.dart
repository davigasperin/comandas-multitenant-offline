import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';

class AuthTenantInterceptor extends Interceptor {
  final FlutterSecureStorage _storage;

  AuthTenantInterceptor(this._storage);

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      final token = await _storage.read(key: AppConstants.storageKeyAccessToken);
      final tenant = await _storage.read(key: AppConstants.storageKeySelectedTenantId);
      final owner = await _storage.read(key: AppConstants.storageKeyUserId);
      if (options.extra['offlineReplay'] == true) {
        handler.reject(DioException(requestOptions: options,
          message: 'Legacy offline queue cannot safely identify its authenticated owner.'));
        return;
      }
      options.headers.remove('Authorization');
      options.headers.remove(AppConstants.tenantHeaderKey);
      options.extra.remove('owner');
      if (token != null && options.path != '/auth/login') {
        options.headers['Authorization'] = 'Bearer $token';
        if (tenant != null) options.headers[AppConstants.tenantHeaderKey] = tenant;
        if (owner != null) options.extra['owner'] = owner;
      }
      handler.next(options);
    } catch (error) {
      handler.reject(DioException(requestOptions: options, error: error,
        message: 'Unable to read authenticated session.'));
    }
  }
}
