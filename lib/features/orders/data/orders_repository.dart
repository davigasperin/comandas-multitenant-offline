import 'package:dio/dio.dart';

import '../../../core/errors/api_exception.dart';
import '../domain/order_model.dart';
import '../domain/product_model.dart';

class OrdersRepository {
  final Dio _dio;

  OrdersRepository(this._dio);

  /// Lista as comandas do tenant ativo (o tenant já vai no header,
  /// injetado pelo AuthTenantInterceptor — não precisa passar aqui).
  Future<List<Order>> getOpenOrders() =>
      _getAllOrders('open,sentToKitchen,delivered');

  Future<List<Order>> getClosedOrders() => _getAllOrders('closed');

  Future<List<Order>> _getAllOrders(String status) async {
    final orders = <Order>[];
    String? cursor;

    try {
      do {
        final response = await _dio.get('/orders', queryParameters: {
          'status': status,
          'limit': 100,
          if (cursor != null) 'cursor': cursor,
        });
        final payload = response.data as Map<String, dynamic>;
        final data = payload['data'] as List<dynamic>;
        orders
            .addAll(data.map((j) => Order.fromJson(j as Map<String, dynamic>)));
        final pagination = payload['pagination'] as Map<String, dynamic>?;
        cursor = pagination?['next_cursor'] as String?;
      } while (cursor != null);
      return orders;
    } on DioException catch (e) {
      _rethrowAsApiException(e);
    }
  }

  Future<Order> createOrder({required String tableLabel}) async {
    try {
      final idempKey = 'idemp_create_${DateTime.now().microsecondsSinceEpoch}';
      final tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';
      final response = await _dio.post(
        '/orders',
        data: {'table_label': tableLabel},
        options: Options(
          headers: {'X-Idempotency-Key': idempKey},
          extra: {'tempOrderId': tempId},
        ),
      );
      if (response.statusCode == 202) {
        return Order(
          id: tempId,
          tableLabel: tableLabel,
          status: OrderStatus.open,
          items: const [],
          openedAt: DateTime.now(),
        );
      }
      return Order.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 202) {
        final assignedId =
            e.response?.data is Map && e.response?.data['id'] != null
                ? e.response!.data['id'].toString()
                : 'temp_${DateTime.now().microsecondsSinceEpoch}';
        return Order(
          id: assignedId,
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
      return data
          .map((j) => Product.fromJson(j as Map<String, dynamic>))
          .toList();
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
      final idempKey = 'idemp_item_${DateTime.now().microsecondsSinceEpoch}';
      final response = await _dio.post(
        '/orders/$orderId/items',
        data: {
          'product_id': productId,
          'quantity': quantity,
          'notes': notes,
        },
        options: Options(
          headers: {'X-Idempotency-Key': idempKey},
          extra: orderId.startsWith('temp_')
              ? {'dependsOnTempOrderId': orderId}
              : {},
        ),
      );
      if (response.statusCode == 202) {
        return Order(
          id: orderId,
          tableLabel: '...',
          status: OrderStatus.open,
          items: const [],
          openedAt: DateTime.now(),
        );
      }
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

  Future<SettlementPreview> previewSettlement({
    required String orderId,
    int discountCents = 0,
    int serviceFeeBps = 1000,
  }) async {
    try {
      final response = await _dio.post(
        '/orders/$orderId/settlement-preview',
        data: {
          'discount_cents': discountCents,
          'service_fee_bps': serviceFeeBps,
        },
      );
      return SettlementPreview.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _rethrowAsApiException(e);
    }
  }

  Future<bool> settleOrder({
    required String orderId,
    required List<Map<String, dynamic>> payments,
    int discountCents = 0,
    int serviceFeeBps = 1000,
    int? expectedVersion,
    String? idempotencyKey,
  }) async {
    try {
      final key = idempotencyKey ??
          'idemp_settle_${DateTime.now().microsecondsSinceEpoch}';
      final response = await _dio.post(
        '/orders/$orderId/settle',
        data: {
          'payments': payments,
          'discount_cents': discountCents,
          'service_fee_bps': serviceFeeBps,
          if (expectedVersion != null) 'expected_version': expectedVersion,
        },
        options: Options(
          headers: {'X-Idempotency-Key': key},
          extra: {'skipOfflineQueue': true},
        ),
      );
      return response.statusCode != 202 && response.extra['queued'] != true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 202 ||
          e.response?.extra['queued'] == true) {
        throw ApiException.unknown(
            'Liquidação financeira não pode ser enfileirada offline.');
      }
      _rethrowAsApiException(e);
    }
  }

  Future<bool> closeOrder(String orderId, {int? expectedVersion}) async {
    try {
      final idempKey = 'idemp_close_${DateTime.now().microsecondsSinceEpoch}';
      final response = await _dio.post(
        '/orders/$orderId/close',
        data: {
          if (expectedVersion != null) 'expected_version': expectedVersion,
        },
        options: Options(
          headers: {'X-Idempotency-Key': idempKey},
          extra: orderId.startsWith('temp_')
              ? {'dependsOnTempOrderId': orderId}
              : {},
        ),
      );
      if (response.statusCode == 202 || response.extra['queued'] == true) {
        return false;
      }
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 202 ||
          e.response?.extra['queued'] == true) {
        return false;
      }
      _rethrowAsApiException(e);
    }
  }

  Future<bool> updateOrderStatus({
    required String orderId,
    required String status,
    int? expectedVersion,
  }) async {
    try {
      final idempKey = 'idemp_status_${DateTime.now().microsecondsSinceEpoch}';
      final response = await _dio.patch(
        '/orders/$orderId/status',
        data: {
          'status': status,
          if (expectedVersion != null) 'expected_version': expectedVersion,
        },
        options: Options(
          headers: {'X-Idempotency-Key': idempKey},
          extra: orderId.startsWith('temp_')
              ? {'dependsOnTempOrderId': orderId}
              : {},
        ),
      );
      if (response.statusCode == 202 || response.extra['queued'] == true) {
        return false;
      }
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 202 ||
          e.response?.extra['queued'] == true) {
        return false;
      }
      _rethrowAsApiException(e);
    }
  }

  Never _rethrowAsApiException(DioException e) {
    if (e.response?.statusCode == 401) throw ApiException.unauthorized();
    if (e.type == DioExceptionType.connectionError) {
      throw ApiException.network();
    }
    throw ApiException.unknown(e.message);
  }
}
