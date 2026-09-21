class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  factory ApiException.unauthorized() =>
      const ApiException('Sessão expirada. Faça login novamente.',
          statusCode: 401);

  factory ApiException.noTenantSelected() =>
      const ApiException('Nenhuma empresa selecionada.');

  factory ApiException.network() =>
      const ApiException('Falha de conexão. Verifique sua internet.');

  factory ApiException.unknown([String? detail]) =>
      ApiException(detail ?? 'Erro inesperado. Tente novamente.');

  @override
  String toString() => message;
}
