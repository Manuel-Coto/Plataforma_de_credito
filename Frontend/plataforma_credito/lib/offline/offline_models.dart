import 'dart:convert';

import '../services/api_exception.dart';

class OfflineQueuedException extends ApiException {
  OfflineQueuedException(this.operationId)
      : super(
            'Cambio guardado en este equipo. Está pendiente de sincronización.');

  final String operationId;
}

enum OutboxStatus { pending, conflict, error }

class OfflineScope {
  OfflineScope(
      {required this.baseUrl, required this.userId, required this.role}) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        userId.trim().isEmpty ||
        !['pyme', 'inversionista', 'administrador'].contains(role)) {
      throw const FormatException('Ámbito de sesión inválido.');
    }
  }
  final String baseUrl;
  final String userId;
  final String role;
  String get key => jsonEncode([baseUrl, userId, role]);
  Map<String, dynamic> toJson() =>
      {'baseUrl': baseUrl, 'userId': userId, 'role': role};
  factory OfflineScope.fromJson(Map<String, dynamic> json) => OfflineScope(
      baseUrl: json['baseUrl'] as String,
      userId: json['userId'] as String,
      role: json['role'] as String);
}

class CachedGet {
  const CachedGet(
      {required this.body, required this.headers, required this.cachedAt});
  final String body;
  final Map<String, String> headers;
  final DateTime cachedAt;
  Map<String, dynamic> toJson() => {
        'body': body,
        'headers': headers,
        'cachedAt': cachedAt.toIso8601String()
      };
  factory CachedGet.fromJson(Map<String, dynamic> json) => CachedGet(
      body: json['body'] as String,
      headers: Map<String, String>.from(json['headers'] as Map),
      cachedAt: DateTime.parse(json['cachedAt'] as String).toUtc());
}

class OutboxOperation {
  const OutboxOperation(
      {required this.id,
      required this.method,
      required this.route,
      required this.body,
      required this.idempotencyKey,
      required this.ifMatch,
      required this.createdAt,
      required this.status,
      required this.attempts,
      this.lastError,
      this.lastStatus});
  final String id;
  final String method;
  final String route;
  final Map<String, dynamic> body;
  final String idempotencyKey;
  final String? ifMatch;
  final DateTime createdAt;
  final OutboxStatus status;
  final int attempts;
  final String? lastError;
  final int? lastStatus;
  OutboxOperation copyWith(
          {OutboxStatus? status,
          int? attempts,
          String? ifMatch,
          String? lastError,
          int? lastStatus,
          bool clearError = false}) =>
      OutboxOperation(
          id: id,
          method: method,
          route: route,
          body: body,
          idempotencyKey: idempotencyKey,
          ifMatch: ifMatch ?? this.ifMatch,
          createdAt: createdAt,
          status: status ?? this.status,
          attempts: attempts ?? this.attempts,
          lastError: clearError ? null : lastError ?? this.lastError,
          lastStatus: clearError ? null : lastStatus ?? this.lastStatus);
  Map<String, dynamic> toJson() => {
        'id': id,
        'method': method,
        'route': route,
        'body': body,
        'idempotencyKey': idempotencyKey,
        'ifMatch': ifMatch,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'attempts': attempts,
        'lastError': lastError,
        'lastStatus': lastStatus
      };
  factory OutboxOperation.fromJson(Map<String, dynamic> json) {
    final operation = OutboxOperation(
        id: json['id'] as String,
        method: json['method'] as String,
        route: json['route'] as String,
        body: Map.unmodifiable(Map<String, dynamic>.from(json['body'] as Map)),
        idempotencyKey: json['idempotencyKey'] as String,
        ifMatch: json['ifMatch'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
        status: OutboxStatus.values.byName(json['status'] as String),
        attempts: json['attempts'] as int,
        lastError: json['lastError'] as String?,
        lastStatus: json['lastStatus'] as int?);
    if (operation.id.isEmpty ||
        operation.idempotencyKey.isEmpty ||
        operation.attempts < 0 ||
        operation.attempts > 3 ||
        !safeOfflineMutation(operation.method, operation.route, operation.body,
            operation.ifMatch)) {
      throw const FormatException('Cambio local incompatible.');
    }
    return operation;
  }
}

/// No permissions, states, payments, banking, DTE verification or credentials.
bool safeOfflineMutation(
    String method, String route, Map<String, dynamic> body, String? ifMatch) {
  const company = {'nombre', 'nit', 'correo', 'telefono', 'direccion'};
  const invoice = {
    'empresa_id',
    'numero',
    'codigo_generacion',
    'moneda',
    'monto_total_centavos',
    'fecha_emision',
    'fecha_vencimiento'
  };
  if (!safeToPersist(body)) return false;
  if ((method == 'POST' && route == '/api/empresas') ||
      (method == 'PUT' &&
          RegExp(r'^/api/empresas/[^/?#]+$').hasMatch(route) &&
          ifMatch != null &&
          RegExp(r'^"[A-Za-z0-9-]+"$').hasMatch(ifMatch))) {
    return body.keys.toSet().containsAll(company) &&
        body.length == company.length &&
        body.values.every((value) => value is String);
  }
  if (method == 'POST' && route == '/api/facturas') {
    return body.keys.toSet().containsAll(invoice) &&
        body.length == invoice.length &&
        body['monto_total_centavos'] is int &&
        body.entries.every((entry) =>
            entry.key == 'monto_total_centavos' || entry.value is String);
  }
  return false;
}

bool safeToPersist(Object? value) {
  const forbidden = {
    'password',
    'password_hash',
    'contraseña',
    'access_token',
    'refresh_token',
    'authorization',
    'jwt_secret',
    'couchdb_password',
    'token',
    'secret'
  };
  if (value is Map) {
    return value.entries.every((entry) =>
        entry.key is String &&
        !forbidden.contains((entry.key as String).toLowerCase()) &&
        safeToPersist(entry.value));
  }
  if (value is List) return value.every(safeToPersist);
  return value == null || value is String || value is num || value is bool;
}

class SyncSummary {
  const SyncSummary(
      {required this.sent,
      required this.pending,
      required this.conflicts,
      required this.errors});
  final int sent;
  final int pending;
  final int conflicts;
  final int errors;
}
