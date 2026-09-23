import 'package:dio/dio.dart';

Future<List<Map<String, dynamic>>> getAllPages(
  Dio dio,
  String path, {
  Map<String, dynamic>? queryParameters,
}) async {
  final items = <Map<String, dynamic>>[];
  String? cursor;
  do {
    final response = await dio.get(path, queryParameters: {
      ...?queryParameters,
      'limit': 100,
      if (cursor != null) 'cursor': cursor,
    });
    final payload = Map<String, dynamic>.from(response.data as Map);
    items.addAll((payload['data'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map)));
    cursor = (payload['pagination'] as Map?)?['next_cursor'] as String?;
  } while (cursor != null);
  return items;
}
