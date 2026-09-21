import 'package:dio/dio.dart';

import '../../../core/errors/api_exception.dart';
import '../domain/order_model.dart';
import '../domain/product_model.dart';

class OrdersRepository {
  final Dio _dio;

  OrdersRepository(this._dio);

  /// Lista as comandas do tenant ativo (o tenant já vai no header,
  /// injetado pelo AuthTenantInterceptor — não precisa passar aqui).
  Future<List<Order>> getOpenOrders() async {
    try {
      final response = await _dio.get('/orders', queryParameters: {
        'status': 'open,sentToKitchen,delivered',
      });
      final data = response.data['data'] as List<dynamic>;
      return data.map((j) => Order.fromJson(j as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      _rethrowAsApiException(e);
    }
  }

  Future<List<Order>> getClosedOrders() async {
    try {
      final response = await _dio.get('/orders', queryParameters: {
        'status': 'closed',
      });
      final data = response.data['data'] as List<dynamic>;
      return data.map((j) => Order.fromJson(j as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      _rethrowAsApiException(e);
    }
  }

  Future<Order> createOrder({required String tableLabel}) async {
    try {
      final response = await _dio.post(
        '/orders', 
        data: {'table_label': tableLabel},
        options: Options(headers: {'X-Idempotency-Key': DateTime.now().toIso8601String()}),
      );
      return Order.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 202) {
        return Order(
          id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
          tableLabel: tableLabel,
          status: OrderStatus.open,
          items: const [],
          openedAt: DateTime.now(),
        );
      }
      _rethrowAsApiException(e);
    }
  }

  Future<Order> getOrderById(String id) async {
    try {
      final response = await _dio.get('/orders/$id');
      return Order.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _rethrowAsApiException(e);
    }
  }

  Future<List<Product>> getProducts() async {
    try {
      final response = await _dio.get('/orders/products');
      final data = response.data['data'] as List<dynamic>;
      return data.map((j) => Product.fromJson(j as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      _rethrowAsApiException(e);
    }
  }

  Future<Order> addItem({
    required String orderId,
    required String productId,
    required int quantity,
    String? notes,
  }) async {
    try {
      final response = await _dio.post(
        '/orders/$orderId/items', 
        data: {
          'product_id': productId,
          'quantity': quantity,
          'notes': notes,
        },
        options: Options(headers: {'X-Idempotency-Key': DateTime.now().toIso8601String()}),
      );
      return Order.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 202) {
        return Order(
          id: orderId,
          tableLabel: '...',
          status: OrderStatus.open,
          items: const [],
          openedAt: DateTime.now(),
        );
      }
      _rethrowAsApiException(e);
    }
  }

  Future<void> closeOrder(String orderId) async {
    try {
      await _dio.post('/orders/$orderId/close',
          options: Options(headers: {'X-Idempotency-Key': DateTime.now().toIso8601String()}));
    } on DioException catch (e) {
      if (e.response?.statusCode == 202) return;
      _rethrowAsApiException(e);
    }
  }

  Future<void> updateOrderStatus({required String orderId, required String status}) async {
    try {
      await _dio.patch(
        '/orders/$orderId/status',
        data: {'status': status},
        options: Options(headers: {'X-Idempotency-Key': DateTime.now().toIso8601String()}),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 202) return;
      _rethrowAsApiException(e);
    }
  }

  Never _rethrowAsApiException(DioException e) {
    if (e.response?.statusCode == 401) throw ApiException.unauthorized();
    if (e.type == DioExceptionType.connectionError) throw ApiException.network();
    throw ApiException.unknown(e.message);
  }
}
