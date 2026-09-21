import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/api_exception.dart';
import '../domain/auth_models.dart';

class AuthRepository {
  final Dio _dio;
  final FlutterSecureStorage _storage;

  AuthRepository(this._dio, this._storage);

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });

      final result = AuthResult.fromJson(response.data as Map<String, dynamic>);
      await _persistSession(result);
      return result;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const ApiException('E-mail ou senha inválidos.', statusCode: 401);
      }
      throw ApiException.unknown(e.message);
    }
  }

  Future<AuthResult?> refresh() async {
    final refreshToken =
        await _storage.read(key: AppConstants.storageKeyRefreshToken);
    if (refreshToken == null) return null;
    try {
      final response = await _dio.post('/auth/refresh', data: {
        'refresh_token': refreshToken,
      });
      final result = AuthResult.fromJson(response.data as Map<String, dynamic>);
      await _persistSession(result);
      return result;
    } on DioException {
      await _clearSession();
      return null;
    }
  }

  Future<void> _persistSession(AuthResult result) async {
    await _storage.write(
      key: AppConstants.storageKeyAccessToken,
      value: result.accessToken,
    );
    await _storage.write(
      key: AppConstants.storageKeyRefreshToken,
      value: result.refreshToken,
    );
    await _storage.write(
      key: AppConstants.storageKeyUserId,
      value: result.user.id,
    );
    await _storage.delete(key: 'logout_pending');
  }

  Future<void> logout() async {
    final refreshToken =
        await _storage.read(key: AppConstants.storageKeyRefreshToken);
    if (refreshToken != null) {
      try {
        await _dio.post('/auth/logout', data: {'refresh_token': refreshToken});
      } on DioException {
        await _storage.write(key: 'logout_pending', value: 'true');
      }
    }
    await _clearSession();
  }

  Future<void> _clearSession() async {
    await _storage.delete(key: AppConstants.storageKeyAccessToken);
    await _storage.delete(key: AppConstants.storageKeyRefreshToken);
    await _storage.delete(key: AppConstants.storageKeySelectedTenantId);
    await _storage.delete(key: AppConstants.storageKeyUserId);
  }

  Future<bool> hasValidSession() async {
    final refreshToken =
        await _storage.read(key: AppConstants.storageKeyRefreshToken);
    if (refreshToken == null) {
      await _clearSession();
      return false;
    }
    return await refresh() != null;
  }
}
