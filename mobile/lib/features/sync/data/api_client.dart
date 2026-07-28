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

  /// Forwards a peer's queued outbox through the relay. The server still
  /// re-verifies every bulletin signature and deduplicates by `sha256`
  /// and request `id`, so this is the same idempotent insertion path as
  /// `/api/v1/sync` — just labelled "mesh/forward" so audit logs can
  /// distinguish carrier traffic from same-phone traffic.
  Future<Map<String, dynamic>> meshForward({
    required String forwarderPeerId,
    required List<Map<String, dynamic>> bulletins,
    required List<Map<String, dynamic>> requests,
  }) async {
    final r = await _dio.post('/api/v1/mesh/forward', data: {
      'forwarder_peer_id': forwarderPeerId,
      'bulletins': bulletins,
      'requests': requests,
    });
    if (r.statusCode != 200) {
      throw Exception('meshForward: ${r.statusCode} ${r.data}');
    }
    return r.data as Map<String, dynamic>;
  }

  String get baseUrl => _dio.options.baseUrl;

  /// Fetches a moderator's registered public key (base64). Used to
  /// verify peer-received bulletin signatures locally so the phone
  /// never trusts a peer's word that a bulletin is signed.
  ///
  /// Returns `null` if the moderator is unknown or the request fails.
  Future<String?> fetchModeratorPublicKeyB64(String moderatorId) async {
    try {
      final r = await _dio.get('/api/v1/moderators/$moderatorId');
      if (r.statusCode != 200) return null;
      final m = r.data as Map<String, dynamic>;
      return m['public_key_b64'] as String?;
    } catch (_) {
      return null;
    }
  }
}