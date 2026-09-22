import 'package:dio/dio.dart';
import '../domain/catalog_models.dart';

class CatalogRepository {
  final Dio dio;
  CatalogRepository(this.dio);

  Future<List<CatalogCategory>> categories() async {
    final response = await dio.get('/categories', queryParameters: {'all': true});
    return (response.data['data'] as List)
        .map((e) => CatalogCategory.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<CatalogProduct>> products() async {
    final response = await dio.get('/products', queryParameters: {'all': true});
    return (response.data['data'] as List)
        .map((e) => CatalogProduct.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<DiningTableModel>> tables() async {
    final response = await dio.get('/tables');
    return (response.data['data'] as List)
        .map((e) => DiningTableModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> createProduct({
    required String name,
    required int priceCents,
    int costCents = 0,
    bool stockControlled = false,
    num minimumStock = 0,
    String? categoryId,
    bool available = true,
    int sortOrder = 0,
  }) {
    return dio.post(
      '/products',
      data: {
        'name': name,
        'price_cents': priceCents,
        'cost_cents': costCents,
        'stock_controlled': stockControlled,
        'minimum_stock': minimumStock,
        if (categoryId != null) 'category_id': categoryId,
        'available': available,
        'sort_order': sortOrder,
      },
      options: Options(extra: {'skipOfflineQueue': true}),
    );
  }

  Future<void> updateProduct({
    required String id,
    required String name,
    required int priceCents,
    int? costCents,
    bool? stockControlled,
    num? minimumStock,
    String? categoryId,
    required bool available,
    required int sortOrder,
    bool? active,
  }) {
    return dio.patch(
      '/products/$id',
      data: {
        'name': name,
        'price_cents': priceCents,
        if (costCents != null) 'cost_cents': costCents,
        if (stockControlled != null) 'stock_controlled': stockControlled,
        if (minimumStock != null) 'minimum_stock': minimumStock,
        'category_id': categoryId,
        'available': available,
        'sort_order': sortOrder,
        if (active != null) 'active': active,
      },
      options: Options(extra: {'skipOfflineQueue': true}),
    );
  }

  Future<void> setProductAvailability(String id, bool available) {
    return dio.patch(
      '/products/$id',
      data: {'available': available},
      options: Options(extra: {'skipOfflineQueue': true}),
    );
  }

  Future<void> deleteProduct(String id) {
    return dio.delete(
      '/products/$id',
      options: Options(extra: {'skipOfflineQueue': true}),
    );
  }

  Future<void> restoreProduct(CatalogProduct product) {
    return updateProduct(
      id: product.id,
      name: product.name,
      priceCents: product.priceCents,
      costCents: product.costCents,
      stockControlled: product.stockControlled,
      minimumStock: product.minimumStock,
      categoryId: product.categoryId,
      available: product.available,
      sortOrder: product.sortOrder,
      active: true,
    );
  }
}
