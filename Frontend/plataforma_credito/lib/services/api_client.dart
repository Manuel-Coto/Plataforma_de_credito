import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/config/api_config.dart';
import '../offline/offline_controller.dart';
import '../offline/offline_models.dart';
import '../offline/offline_store.dart';
import 'api_exception.dart';

export 'api_exception.dart';
export '../offline/offline_controller.dart';
export '../offline/offline_models.dart';
export '../offline/offline_store.dart';

/// HTTP client. Authentication is memory-only; encrypted snapshots and safe
/// drafts are bound to the authenticated user, role, server, and session lifetime.
class ApiClient {
  ApiClient(
      {http.Client? httpClient,
      this.baseUrl = ApiConfig.baseUrl,
      String? token,
      OfflineStore? offlineStore,
      OfflineController? offlineController,
      Duration timeout = const Duration(seconds: 10)})
      : _http = httpClient ?? http.Client(),
        _token = token,
        _timeout = timeout,
        offline = offlineController ?? OfflineController(store: offlineStore);

  final http.Client _http;
  final String baseUrl;
  final Duration _timeout;
  final OfflineController offline;
  String? _token;
  bool _closed = false;
  int _cacheGeneration = 0;
  bool _permissionCheckRequired = false;
  final Map<String, Future<dynamic>> _inFlight = {};
  final Map<String, Future<void>> _retryInFlight = {};
  final Map<String, ({String etag, int epoch})> _conflictRevisions = {};
  void Function()? onUnauthorized;
  String? get token => _token;
  set token(String? value) {
    if (value == null && _token != null) {
      offline.endSession();
      _conflictRevisions.clear();
    }
    _token = value;
  }

  Future<void> iniciarSesionOffline(
      {required String userId,
      required String role,
      required DateTime expiresAt}) async {
    final scope = OfflineScope(baseUrl: baseUrl, userId: userId, role: role);
    final activation = offline.activate(scope, expiresAt);
    final epoch = offline.epoch;
    await activation;
    // Only a newly authenticated, still-current scope restores trust. A login
    // cancelled by logout or a newer activation cannot unblock another scope.
    if (offline.current(epoch) && offline.scope?.key == scope.key) {
      _permissionCheckRequired = false;
      _conflictRevisions.clear();
    }
  }

  void terminarSesionOffline() {
    _token = null;
    _conflictRevisions.clear();
    offline.endSession();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _token = null;
    _conflictRevisions.clear();
    _http.close();
    offline.dispose();
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token'
      };
  Uri _uri(String route, Map<String, String>? query) {
    final uri = Uri.parse('$baseUrl$route');
    final parameters = SplayTreeMap<String, String>.from(uri.queryParameters);
    if (query != null) parameters.addAll(query);
    return parameters.isEmpty ? uri : uri.replace(queryParameters: parameters);
  }

  bool _current(int epoch, String? token) =>
      !_closed && token != null && token == _token && offline.current(epoch);

  Future<dynamic> get(String ruta, {Map<String, String>? query}) async =>
      _decode(await _get(ruta, query: query));
  Future<http.Response> getConCabeceras(String ruta) => _get(ruta);

  Future<http.Response> _get(String route, {Map<String, String>? query}) async {
    final uri = _uri(route, query);
    final key = uri.toString();
    final epoch = offline.epoch;
    final cacheGeneration = _cacheGeneration;
    final sentToken = _token;
    final protected = route.startsWith('/api/') &&
        !route.startsWith('/api/auth/') &&
        sentToken != null &&
        offline.active;
    try {
      final response = await _network(() => _http.get(uri, headers: _headers));
      if (protected &&
          _current(epoch, sentToken) &&
          cacheGeneration == _cacheGeneration) {
        final headers = <String, String>{
          'content-type': 'application/json; charset=utf-8',
          if (response.headers['etag'] != null)
            'etag': response.headers['etag']!,
        };
        if (response.bodyBytes.isNotEmpty) {
          await offline.cacheLive(
              key, utf8.decode(response.bodyBytes), headers, epoch);
        }
      }
      return response;
    } on ApiException catch (error) {
      if (protected && _current(epoch, sentToken) && error.status == 403) {
        _permissionCheckRequired = true;
        try {
          await offline.evict(key, epoch);
        } catch (_) {/* Memory was already revoked. */}
        try {
          await _validateOnlineSession();
        } catch (_) {/* Unknown permissions block every cached fallback. */}
      }
      final recoverable = error is _TransportFailure || error.status == 503;
      if (recoverable &&
          protected &&
          !_permissionCheckRequired &&
          _current(epoch, sentToken)) {
        final cached = offline.cached(key, epoch);
        if (cached != null) {
          offline.markSnapshot(key, cached.cachedAt, epoch);
          return http.Response(cached.body, 200, headers: {
            ...cached.headers,
            'x-offline-snapshot': 'true',
            'x-offline-cached-at': cached.cachedAt.toIso8601String()
          });
        }
      }
      rethrow;
    }
  }

  Future<dynamic> post(String ruta, Map<String, dynamic> cuerpo,
          {String? idempotencyKey}) =>
      _mutation('POST', ruta, cuerpo, idempotencyKey: idempotencyKey);
  Future<dynamic> put(String ruta, Map<String, dynamic> cuerpo,
          {String? ifMatch}) =>
      _mutation('PUT', ruta, cuerpo, ifMatch: ifMatch);
  Future<dynamic> patch(String ruta, Map<String, dynamic> cuerpo,
          {String? ifMatch}) =>
      _mutation('PATCH', ruta, cuerpo, ifMatch: ifMatch);
  Future<http.Response> revisarEmpresa(String ruta, String etag) async {
    final epoch = offline.epoch;
    final sentToken = _token;
    final response = await _network(() => _http
        .patch(_uri(ruta, null), headers: {..._headers, 'If-Match': etag}));
    await _invalidateMutation(epoch, sentToken);
    return response;
  }

  Future<void> _invalidateMutation(int epoch, String? sentToken) async {
    if (!_current(epoch, sentToken)) return;
    _cacheGeneration++;
    try {
      await offline.invalidateCache(epoch);
    } catch (_) {
      /* The server acknowledged the mutation; local memory is already invalid. */
    }
  }

  Future<dynamic> _mutation(
      String method, String route, Map<String, dynamic> body,
      {String? idempotencyKey, String? ifMatch}) async {
    if (_token != null &&
        offline.active &&
        safeOfflineMutation(method, route, body, ifMatch)) {
      // Persist before sending, including online: an ambiguous timeout can be
      // replayed with exactly the same identity instead of creating a duplicate.
      final operation = await offline.enqueue(
          method: method,
          route: route,
          body: body,
          idempotencyKey: idempotencyKey,
          ifMatch: ifMatch);
      if (operation.status == OutboxStatus.conflict) {
        throw ApiException(
            'Revisa el conflicto antes de volver a enviar este cambio.', 409);
      }
      return _sendOperation(operation, offline.epoch);
    }
    final epoch = offline.epoch;
    final sentToken = _token;
    final response = await _send(method, route, body,
        idempotencyKey: idempotencyKey, ifMatch: ifMatch);
    await _invalidateMutation(epoch, sentToken);
    return _decode(response);
  }

  Future<http.Response> _send(
      String method, String route, Map<String, dynamic> body,
      {String? idempotencyKey, String? ifMatch}) {
    final headers = {
      ..._headers,
      if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
      if (ifMatch != null) 'If-Match': ifMatch
    };
    final encoded = jsonEncode(body);
    final uri = _uri(route, null);
    return _network(() => switch (method) {
          'POST' => _http.post(uri, headers: headers, body: encoded),
          'PUT' => _http.put(uri, headers: headers, body: encoded),
          'PATCH' => _http.patch(uri, headers: headers, body: encoded),
          _ => throw ApiException('Operación no admitida.'),
        });
  }

  Future<dynamic> _sendOperation(OutboxOperation operation, int epoch) {
    final current = _inFlight[operation.id];
    if (current != null) return current;
    final future = _sendOperationOnce(operation, epoch);
    _inFlight[operation.id] = future;
    void release() {
      if (identical(_inFlight[operation.id], future)) {
        _inFlight.remove(operation.id);
      }
    }

    unawaited(future.then<void>((_) => release(),
        onError: (Object _, StackTrace __) => release()));
    return future;
  }

  Future<dynamic> _sendOperationOnce(
      OutboxOperation requested, int epoch) async {
    final operation = offline.operation(requested.id);
    if (operation == null) {
      throw ApiException('El cambio ya no está pendiente.');
    }
    final sentToken = _token;
    if (!_current(epoch, sentToken)) throw ApiException('La sesión cambió.');
    if (operation.attempts >= 3) {
      throw ApiException(
          'Se alcanzó el límite de intentos. Revisa el cambio antes de reintentarlo.');
    }
    final attempted =
        operation.copyWith(attempts: operation.attempts + 1, clearError: true);
    await offline.replace(attempted, epoch);
    if (!_current(epoch, sentToken)) throw ApiException('La sesión cambió.');
    try {
      final response = await _send(
          operation.method, operation.route, operation.body,
          idempotencyKey: operation.idempotencyKey, ifMatch: operation.ifMatch);
      if (!_current(epoch, sentToken)) throw ApiException('La sesión cambió.');
      final decoded = _decode(response);
      _cacheGeneration++;
      await offline.completed(operation.id, epoch);
      return decoded;
    } on ApiException catch (error) {
      if (!_current(epoch, sentToken)) rethrow;
      if (error is _TransportFailure || error.status == 503) {
        final exhausted = attempted.attempts >= 3;
        await offline.replace(
            attempted.copyWith(
                status: exhausted ? OutboxStatus.error : OutboxStatus.pending,
                lastStatus: error.status,
                lastError: exhausted
                    ? 'Se alcanzaron tres intentos. Revisa y reintenta explícitamente.'
                    : 'Sin conexión con el servicio. Pendiente de sincronización.'),
            epoch);
        throw OfflineQueuedException(operation.id);
      }
      await offline.replace(
          attempted.copyWith(
              status: [409, 412].contains(error.status)
                  ? OutboxStatus.conflict
                  : OutboxStatus.error,
              lastStatus: error.status,
              lastError: [409, 412].contains(error.status)
                  ? 'El recurso cambió o entra en conflicto. Revisa la versión del servidor.'
                  : 'El servidor rechazó el cambio${error.status == null ? '' : ' (HTTP ${error.status})'}.'),
          epoch);
      rethrow;
    } catch (_) {
      if (_current(epoch, sentToken)) {
        await offline.replace(
            attempted.copyWith(
                status: OutboxStatus.error,
                lastError:
                    'Respuesta incompatible. Verifica el recurso antes de reintentar el mismo cambio.'),
            epoch);
      }
      rethrow;
    }
  }

  Future<void> _validateOnlineSession() async {
    final scope = offline.scope;
    final epoch = offline.epoch;
    final sentToken = _token;
    if (scope == null || sentToken == null || _closed) {
      throw ApiException('Inicia sesión en línea para sincronizar.');
    }
    final response = await _network(
        () => _http.get(_uri('/api/usuarios/me', null), headers: _headers));
    if (!_current(epoch, sentToken)) throw ApiException('La sesión cambió.');
    final data = _decode(response);
    if (data is! Map<String, dynamic> ||
        data['id'] is! String ||
        data['rol'] is! String ||
        data['estado'] is! String) {
      throw const FormatException('Perfil de sesión incompatible.');
    }
    if (data['id'] != scope.userId ||
        data['rol'] != scope.role ||
        data['estado'] != 'activo') {
      onUnauthorized?.call();
      terminarSesionOffline();
      throw ApiException(
          'Tu cuenta o sus permisos cambiaron. Inicia sesión nuevamente.', 401);
    }
    _permissionCheckRequired = false;
  }

  Future<SyncSummary> sincronizarPendientes() async {
    if (offline.syncing) {
      throw ApiException('La sincronización ya está en curso.');
    }
    offline.setSyncing(true);
    var sent = 0;
    try {
      await _validateOnlineSession();
      final epoch = offline.epoch;
      for (final operation in offline.operations
          .where((operation) => operation.status == OutboxStatus.pending)
          .toList()) {
        if (!offline.current(epoch)) break;
        try {
          await _sendOperation(operation, epoch);
          sent++;
        } on OfflineQueuedException {
          /* Keep pending/error; explicit next action only. */
        } on ApiException catch (error) {
          if (error.status == 401) rethrow;
        } on FormatException {
          /* Retained as an error, never reported as success. */
        }
      }
      return SyncSummary(
          sent: sent,
          pending: offline.pendingCount,
          conflicts: offline.conflictCount,
          errors: offline.errorCount);
    } finally {
      offline.setSyncing(false);
    }
  }

  Future<http.Response> consultarConflicto(String operationId) async {
    await _validateOnlineSession();
    final operation = offline.operation(operationId);
    if (operation == null || operation.method != 'PUT') {
      throw ApiException('Este conflicto no permite combinar cambios.');
    }
    final epoch = offline.epoch;
    final sentToken = _token;
    final response = await _network(
        () => _http.get(_uri(operation.route, null), headers: _headers));
    if (!_current(epoch, sentToken)) throw ApiException('La sesión cambió.');
    final data = _decode(response);
    final etag = response.headers['etag'];
    final expectedId = Uri.decodeComponent(operation.route.split('/').last);
    if (data is! Map<String, dynamic> ||
        data['id'] != expectedId ||
        etag == null ||
        !RegExp(r'^"[A-Za-z0-9-]+"$').hasMatch(etag)) {
      throw const FormatException('La versión del servidor no es válida.');
    }
    _conflictRevisions[operationId] = (etag: etag, epoch: epoch);
    return response;
  }

  Future<void> reintentarOperacion(String id, {String? ifMatch}) {
    final current = _retryInFlight[id];
    if (current != null) return current;
    final future = _reintentarUnaVez(id, ifMatch: ifMatch);
    _retryInFlight[id] = future;
    void release() {
      if (identical(_retryInFlight[id], future)) _retryInFlight.remove(id);
    }

    unawaited(future.then<void>((_) => release(),
        onError: (Object _, StackTrace __) => release()));
    return future;
  }

  Future<void> _reintentarUnaVez(String id, {String? ifMatch}) async {
    if (offline.syncing) {
      throw ApiException('Espera a que termine la sincronización.');
    }
    await _validateOnlineSession();
    final operation = offline.operation(id);
    if (operation == null) {
      throw ApiException('El cambio ya no está pendiente.');
    }
    final epoch = offline.epoch;
    if (operation.method == 'POST' &&
        operation.status == OutboxStatus.conflict) {
      throw ApiException(
          'Un conflicto de creación solo puede descartarse tras revisar el recurso.',
          409);
    }
    if (ifMatch != null ||
        (operation.method == 'PUT' &&
            operation.status == OutboxStatus.conflict)) {
      final observed = _conflictRevisions.remove(id);
      if (operation.method != 'PUT' ||
          ifMatch == null ||
          observed == null ||
          observed.epoch != epoch ||
          observed.etag != ifMatch) {
        throw ApiException(
            'Consulta primero la versión actual y confirma la resolución del conflicto.');
      }
    }
    final reset = operation.copyWith(
        status: OutboxStatus.pending,
        attempts: 0,
        ifMatch: ifMatch,
        clearError: true);
    await offline.replace(reset, epoch);
    await _sendOperation(reset, epoch);
  }

  Future<http.Response> _network(
      Future<http.Response> Function() request) async {
    if (_closed) throw ApiException('El cliente ya está cerrado.');
    final sentToken = _token;
    try {
      final response = await request().timeout(_timeout);
      if (sentToken != null && sentToken != _token) {
        throw ApiException('La sesión cambió.');
      }
      if (response.statusCode == 401 &&
          sentToken != null &&
          sentToken == _token) {
        onUnauthorized?.call();
        terminarSesionOffline();
      }
      _decode(response);
      if (response.statusCode != 503) offline.connection(true);
      return response;
    } on TimeoutException {
      offline.connection(false);
      throw _TransportFailure('El servidor tardó demasiado en responder.');
    } on http.ClientException {
      offline.connection(false);
      throw _TransportFailure('No se pudo conectar con el servidor.');
    } on SocketException {
      offline.connection(false);
      throw _TransportFailure('No se pudo conectar con el servidor.');
    } on ApiException catch (error) {
      if (error.status == 503) offline.connection(false);
      rethrow;
    }
  }

  dynamic _decode(http.Response response) {
    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return text.isEmpty ? null : jsonDecode(text);
    }
    var message = 'Error ${response.statusCode}';
    try {
      final data = jsonDecode(text);
      if (data is Map && data['error'] is String) {
        message = data['error'] as String;
      }
    } on FormatException {/* Non-JSON errors never become successful data. */}
    throw ApiException(message, response.statusCode);
  }
}

class _TransportFailure extends ApiException {
  _TransportFailure(super.message);
}
