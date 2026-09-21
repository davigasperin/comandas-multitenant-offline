class AppConstants {
  AppConstants._();

  static const String appName = 'Comandas';

  // Ajuste para a URL do backend (ex.: NestJS rodando em produção/local)
  static const String baseUrl = 'http://localhost:3000/v1';
  static const String wsUrl = 'http://localhost:3000/orders';

  // Chaves de storage seguro
  static const String storageKeyAccessToken = 'access_token';
  static const String storageKeyRefreshToken = 'refresh_token';
  static const String storageKeySelectedTenantId = 'selected_tenant_id';
  static const String storageKeySelectedTenantRole = 'selected_tenant_role';
  static const String storageKeyUserId = 'user_id';

  // Header usado para isolar o tenant em cada request
  static const String tenantHeaderKey = 'X-Tenant-Id';
}
