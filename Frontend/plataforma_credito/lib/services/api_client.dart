import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// Cliente HTTP hacia el backend Rust. NUNCA habla directo con CouchDB.
class ApiClient {
  ApiClient({this.baseUrl = 'http://127.0.0.1:8080', this.token});
  final String baseUrl;
  String? token; // lo asigna el módulo 1 (login)

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> get(String path) async {
    try {
      final r = await http
          .get(Uri.parse('$baseUrl$path'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      return _decode(r);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('No se pudo conectar con el servidor. Revisa que el backend esté activo.');
    }
  }

  Future<dynamic> post(String path, Map<String, dynamic> body,
      {String? idempotencyKey}) async {
    try {
      final r = await http
          .post(Uri.parse('$baseUrl$path'),
              headers: {
                ..._headers,
                if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
              },
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 10));
      return _decode(r);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('No se pudo conectar con el servidor. Revisa que el backend esté activo.');
    }
  }

  dynamic _decode(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    }
    throw ApiException('El servidor respondió con error ${r.statusCode}.', r.statusCode);
  }
}
