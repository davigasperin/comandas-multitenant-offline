import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';

class AuthTenantInterceptor extends Interceptor {
  final FlutterSecureStorage _storage;
  final Dio _dio;
  Future<String?>? _refreshing;

  AuthTenantInterceptor(this._storage, this._dio);

  bool _isAuthEndpoint(String path) =>
      path == '/auth/login' ||
      path == '/auth/refresh' ||
      path == '/auth/logout';

  Future<String?> _refreshAccessToken() async {
    final existing = _refreshing;
    if (existing != null) return existing;
    final future = _performRefresh();
    _refreshing = future;
    try {
      return await future;
    } finally {
      _refreshing = null;
    }
  }

  Future<String?> _performRefresh() async {
    final refreshToken =
        await _storage.read(key: AppConstants.storageKeyRefreshToken);
    if (refreshToken == null) return null;
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
        options: Options(extra: {'skipAuthRefresh': true}),
      );
      final data = response.data;
      final access = data?['access_token'] as String?;
      final refresh = data?['refresh_token'] as String?;
      if (access == null || refresh == null) return null;
      await _storage.write(
          key: AppConstants.storageKeyAccessToken, value: access);
      await _storage.write(
          key: AppConstants.storageKeyRefreshToken, value: refresh);
      return access;
    } catch (_) {
      await _clearSession();
      return null;
    }
  }

  Future<void> _clearSession() async {
    await _storage.delete(key: AppConstants.storageKeyAccessToken);
    await _storage.delete(key: AppConstants.storageKeyRefreshToken);
    await _storage.delete(key: AppConstants.storageKeySelectedTenantId);
    await _storage.delete(key: AppConstants.storageKeyUserId);
  }

  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      final token =
          await _storage.read(key: AppConstants.storageKeyAccessToken);
      final tenant =
          await _storage.read(key: AppConstants.storageKeySelectedTenantId);
      final owner = await _storage.read(key: AppConstants.storageKeyUserId);
      if (options.extra['offlineReplay'] == true) {
        final expectedTenant = options.headers['X-Tenant-Id']?.toString();
        final expectedOwner = options.extra['expectedOwner']?.toString();
        if (expectedTenant != null && expectedTenant != tenant) {
          handler.reject(DioException(
            requestOptions: options,
            message: 'Active tenant changed before offline replay dispatch.',
          ));
          return;
        }
        if (expectedOwner != null && expectedOwner != owner) {
          handler.reject(DioException(
            requestOptions: options,
            message: 'Active user changed before offline replay dispatch.',
          ));
          return;
        }
      }
      options.headers.remove('Authorization');
      options.headers.remove(AppConstants.tenantHeaderKey);
      options.extra.remove('owner');
      if (token != null && !_isAuthEndpoint(options.path)) {
        options.headers['Authorization'] = 'Bearer $token';
        if (tenant != null) {
          options.headers[AppConstants.tenantHeaderKey] = tenant;
        }
        if (owner != null) options.extra['owner'] = owner;
      }
      handler.next(options);
    } catch (error) {
      handler.reject(DioException(
          requestOptions: options,
          error: error,
          message: 'Unable to read authenticated session.'));
    }
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    if (err.response?.statusCode != 401 ||
        _isAuthEndpoint(options.path) ||
        options.extra['skipAuthRefresh'] == true ||
        options.extra['authRetried'] == true) {
      handler.next(err);
      return;
    }

    final access = await _refreshAccessToken();
    if (access == null) {
      handler.next(err);
      return;
    }

    try {
      options.extra['authRetried'] = true;
      options.headers['Authorization'] = 'Bearer $access';
      final response = await _dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }
}
