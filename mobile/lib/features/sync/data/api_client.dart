import 'package:dio/dio.dart';

import '../../../core/env.dart';

class ApiClient {
  final Dio _dio;

  ApiClient()
      : _dio = Dio(BaseOptions(
          baseUrl: Env.apiUrl,
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 10),
          headers: {'Content-Type': 'application/json'},
          validateStatus: (s) => s != null && s < 500,
        ));

  Future<bool> ping() async {
    try {
      final r = await _dio.get('/healthz');
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> pullSync({String? since}) async {
    final r = await _dio.get('/api/v1/sync', queryParameters: {
      'since': since ?? '1970-01-01T00:00:00Z',
      'limit': 200,
    });
    if (r.statusCode != 200) {
      throw Exception('pullSync: ${r.statusCode} ${r.data}');
    }
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> pushSync({
    required List<Map<String, dynamic>> bulletins,
    required List<Map<String, dynamic>> requests,
  }) async {
    final r = await _dio.post('/api/v1/sync', data: {
      'bulletins': bulletins,
      'requests': requests,
    });
    if (r.statusCode != 200) {
      throw Exception('pushSync: ${r.statusCode} ${r.data}');
    }
    return r.data as Map<String, dynamic>;
  }

  String get baseUrl => _dio.options.baseUrl;
}