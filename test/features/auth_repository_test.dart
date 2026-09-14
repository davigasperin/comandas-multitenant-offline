import 'package:comandas_app/core/constants/app_constants.dart';
import 'package:comandas_app/core/errors/api_exception.dart';
import 'package:comandas_app/features/auth/data/auth_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/fake_http_client_adapter.dart';
import '../mocks/fake_secure_storage.dart';

void main() {
  late Dio dio;
  late FakeSecureStorage storage;
  late AuthRepository repository;

  setUp(() {
    dio = Dio();
    storage = FakeSecureStorage();
    repository = AuthRepository(dio, storage);
  });

  test('login saves tokens and returns AuthResult on success (200)', () async {
    dio.httpClientAdapter = FakeHttpClientAdapter((options) async {
      return FakeHttpClientAdapter.json({
        'user': {'id': '1', 'name': 'Demo', 'email': 'demo@comandas.com'},
        'access_token': 'fake_access',
        'refresh_token': 'fake_refresh',
      }, 200);
    });

    final result = await repository.login(email: 'test', password: 'password');

    expect(result.user.name, 'Demo');
    expect(result.accessToken, 'fake_access');

    final savedAccess = await storage.read(key: AppConstants.storageKeyAccessToken);
    expect(savedAccess, 'fake_access');
  });

  test('login throws ApiException with status 401 on unauthorized', () async {
    dio.httpClientAdapter = FakeHttpClientAdapter((options) async {
      return FakeHttpClientAdapter.json({'message': 'Unauthorized'}, 401);
    });

    expect(
      () => repository.login(email: 'test', password: 'wrong'),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
      ),
    );
  });

  test('logout clears secure storage keys', () async {
    await storage.write(key: AppConstants.storageKeyAccessToken, value: 'token');
    await storage.write(key: AppConstants.storageKeySelectedTenantId, value: 'ten_1');

    await repository.logout();

    expect(await storage.read(key: AppConstants.storageKeyAccessToken), isNull);
    expect(await storage.read(key: AppConstants.storageKeySelectedTenantId), isNull);
  });
}
