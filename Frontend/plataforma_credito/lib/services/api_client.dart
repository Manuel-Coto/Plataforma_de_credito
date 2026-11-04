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
  void Function()? onUnauthorized;

  void close() => _http.close();

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

  /// GET que además devuelve el ETag de la respuesta (con sus comillas),
  /// necesario para las operaciones protegidas con If-Match.
  Future<({dynamic cuerpo, String? etag})> getConEtag(
      String ruta, {
        Map<String, String>? query,
      }) async {
    final respuesta = await _ejecutar(
          () => _http.get(_uri(ruta, query), headers: _headers),
    );
    return (cuerpo: _decodificar(respuesta), etag: respuesta.headers['etag']);
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

  /// PATCH opcionalmente condicionado con If-Match (ETag fuerte, con comillas).
  Future<dynamic> patch(
      String ruta, {
        Map<String, dynamic>? cuerpo,
        String? ifMatch,
      }) {
    return _enviar(() => _http.patch(
      _uri(ruta, null),
      headers: {
        ..._headers,
        if (ifMatch != null) 'If-Match': ifMatch,
      },
      body: cuerpo == null ? null : jsonEncode(cuerpo),
    ));
  }

  Future<dynamic> _enviar(Future<http.Response> Function() peticion) async {
    final respuesta = await _ejecutar(peticion);
    return _decodificar(respuesta);
  }

  /// Ejecuta la petición, maneja timeout y 401, y lanza ApiException si el
  /// estado no es 2xx. Devuelve la respuesta cruda cuando fue exitosa.
  Future<http.Response> _ejecutar(
      Future<http.Response> Function() peticion,
      ) async {
    final tokenEnviado = token;
    try {
      final respuesta = await peticion().timeout(_tiempoMaximo);
      if (respuesta.statusCode == 401 &&
          tokenEnviado != null && tokenEnviado == token) {
        onUnauthorized?.call();
      }
      _validar(respuesta);
      return respuesta;
    } on TimeoutException {
      throw ApiException('El servidor tardó demasiado en responder.');
    } on http.ClientException catch (e) {
      throw ApiException('No se pudo conectar con el servidor: ${e.message}');
    }
  }

  void _validar(http.Response respuesta) {
    final exito = respuesta.statusCode >= 200 && respuesta.statusCode < 300;
    if (exito) return;

    // Error: el backend manda {"error": "..."}. Si no es JSON, mensaje genérico.
    final texto = utf8.decode(respuesta.bodyBytes);
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

  dynamic _decodificar(http.Response respuesta) {
    final texto = utf8.decode(respuesta.bodyBytes);
    return texto.isEmpty ? null : jsonDecode(texto);
  }
}