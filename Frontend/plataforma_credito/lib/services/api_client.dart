import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config/api_config.dart';
import 'api_exception.dart';

class ApiClient {
  ApiClient({http.Client? httpClient, this.token})
      : _http = httpClient ?? http.Client();

  final http.Client _http;
  String? token; // se asigna después del login

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Uri _uri(String ruta, Map<String, String>? query) {
    final base = Uri.parse('${ApiConfig.baseUrl}$ruta');
    if (query == null || query.isEmpty) return base;
    return base.replace(queryParameters: query);
  }

  Future<dynamic> get(String ruta, {Map<String, String>? query}) =>
      _enviar(() => _http.get(_uri(ruta, query), headers: _headers));

  Future<dynamic> post(String ruta, Map<String, dynamic> cuerpo) => _enviar(
        () => _http.post(
      _uri(ruta, null),
      headers: _headers,
      body: jsonEncode(cuerpo),
    ),
  );

  Future<dynamic> _enviar(Future<http.Response> Function() peticion) async {
    try {
      return _procesar(await peticion());
    } on http.ClientException {
      throw const ApiException(0, 'No se pudo conectar con el servidor');
    }
  }

  dynamic _procesar(http.Response respuesta) {
    // bodyBytes + utf8: así las tildes y la ñ llegan bien.
    final texto = utf8.decode(respuesta.bodyBytes);
    final datos = texto.isEmpty ? null : jsonDecode(texto);

    if (respuesta.statusCode >= 200 && respuesta.statusCode < 300) {
      return datos;
    }

    final mensaje = (datos is Map && datos['error'] is String)
        ? datos['error'] as String
        : 'Error ${respuesta.statusCode}';
    throw ApiException(respuesta.statusCode, mensaje);
  }
}