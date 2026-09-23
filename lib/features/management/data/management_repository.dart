import 'package:dio/dio.dart';
import '../../../core/network/pagination.dart';

class ManagementRepository {
  final Dio _dio;

  ManagementRepository(this._dio);

  Future<Map<String, dynamic>> getEntitlements() async {
    final response = await _dio.get('/settings/entitlements');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getPrinterSetting() async {
    final response = await _dio.get('/settings/printer');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> getExpenses() =>
      getAllPages(_dio, '/finance/expenses');

  Future<List<Map<String, dynamic>>> getStock() =>
      getAllPages(_dio, '/inventory/stock');

  Future<List<Map<String, dynamic>>> getEmployees() async {
    final response = await _dio.get('/employees');
    return (response.data['data'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> getProfitMargin({
    required DateTime from,
    required DateTime to,
    String cmvMode = 'product_cost',
    String expenseAxis = 'competence',
  }) async {
    final response = await _dio.get('/reports/profit-margin', queryParameters: {
      'from': from.toUtc().toIso8601String(),
      'to': to.toUtc().toIso8601String(),
      'cmv_mode': cmvMode,
      'expense_axis': expenseAxis,
    });
    return Map<String, dynamic>.from(response.data as Map);
  }
}
