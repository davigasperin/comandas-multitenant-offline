import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/api_exception.dart';
import '../domain/tenant_model.dart';

class TenantRepository {
  final Dio _dio;
  final FlutterSecureStorage _storage;

  TenantRepository(this._dio, this._storage);

  /// Lista os tenants (empresas) que o usuário autenticado pode acessar.
  Future<List<Tenant>> getMyTenants() async {
    try {
      final response = await _dio.get('/me/tenants');
      final data = response.data['data'] as List<dynamic>;
      return data
          .map((json) => Tenant.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) throw ApiException.unauthorized();
      throw ApiException.unknown(e.message);
    }
  }

  /// Persiste o tenant ativo localmente. Toda chamada subsequente à API
  /// passa a carregar esse id no header X-Tenant-Id (ver AuthTenantInterceptor).
  Future<void> selectTenant(Tenant tenant) async {
    await _storage.write(
      key: AppConstants.storageKeySelectedTenantId,
      value: tenant.id,
    );
  }

  Future<String?> getSelectedTenantId() {
    return _storage.read(key: AppConstants.storageKeySelectedTenantId);
  }
}
