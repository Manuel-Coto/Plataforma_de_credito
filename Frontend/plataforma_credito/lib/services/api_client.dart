import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config/api_config.dart';
import 'api_exception.dart';

// Re-exporta ApiException: quien importe api_client.dart la recibe también.
// Así el código de los demás módulos sigue funcionando sin cambios.
export 'api_exception.dart';

/// Cliente HTTP hacia el backend Rust. NUNCA habla directo con CouchDB.
class ApiClient {
  ApiClient({
    http.Client? httpClient,
    this.baseUrl = ApiConfig.baseUrl,
    this.token,
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final String baseUrl;
  String? token; // lo asigna el módulo 1 (login)

  static const Duration _tiempoMaximo = Duration(seconds: 10);

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Uri _uri(String ruta, Map<String, String>? query) {
    final uri = Uri.parse('$baseUrl$ruta');
    return (query == null || query.isEmpty)
        ? uri
        : uri.replace(queryParameters: query);
  }

  Future<dynamic> get(String ruta, {Map<String, String>? query}) {
    return _enviar(() => _http.get(_uri(ruta, query), headers: _headers));
  }

  Future<dynamic> post(
      String ruta,
      Map<String, dynamic> cuerpo, {
        String? idempotencyKey,
      }) {
    return _enviar(() => _http.post(
      _uri(ruta, null),
      headers: {
        ..._headers,
        if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
      },
      body: jsonEncode(cuerpo),
    ));
  }

  Future<dynamic> _enviar(Future<http.Response> Function() peticion) async {
    try {
      final respuesta = await peticion().timeout(_tiempoMaximo);
      return _procesar(respuesta);
    } on TimeoutException {
      throw ApiException('El servidor tardó demasiado en responder.');
    } on http.ClientException catch (e) {
      throw ApiException('No se pudo conectar con el servidor: ${e.message}');
    }
  }

  dynamic _procesar(http.Response respuesta) {
    final texto = utf8.decode(respuesta.bodyBytes);
    final exito = respuesta.statusCode >= 200 && respuesta.statusCode < 300;

    if (exito) {
      return texto.isEmpty ? null : jsonDecode(texto);
    }

    // Error: el backend manda {"error": "..."}. Si no es JSON, mensaje genérico.
    String mensaje = 'Error ${respuesta.statusCode}';
    try {
      final datos = jsonDecode(texto);
      if (datos is Map && datos['error'] is String) {
        mensaje = datos['error'] as String;
      }
    } on FormatException {
      // cuerpo que no es JSON: se queda el mensaje genérico
    }
    throw ApiException(mensaje, respuesta.statusCode);
  }
}
