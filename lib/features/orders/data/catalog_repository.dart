import 'package:dio/dio.dart';
import '../domain/catalog_models.dart';

class CatalogRepository {
  final Dio dio;
  CatalogRepository(this.dio);

  Future<List<CatalogCategory>> categories() async {
    final response = await dio.get('/categories', queryParameters: {'all': true});
    return (response.data['data'] as List).map((e) => CatalogCategory.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<List<CatalogProduct>> products() async {
    final response = await dio.get('/products', queryParameters: {'all': true});
    return (response.data['data'] as List).map((e) => CatalogProduct.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<List<DiningTableModel>> tables() async {
    final response = await dio.get('/tables');
    return (response.data['data'] as List).map((e) => DiningTableModel.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> save(String resource, Map<String, dynamic> data, {String? id}) async {
    final options = Options(extra: {'skipOfflineQueue': true});
    if (id == null) {
      await dio.post('/$resource', data: data, options: options);
    } else {
      await dio.patch('/$resource/$id', data: data, options: options);
    }
  }

  Future<void> disable(String resource, String id) async {
    await dio.delete('/$resource/$id', options: Options(extra: {'skipOfflineQueue': true}));
  }
}
