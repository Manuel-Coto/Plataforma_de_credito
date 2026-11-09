import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../services/api_exception.dart';
import 'offline_models.dart';
import 'offline_store.dart';

class OfflineController extends ChangeNotifier {
  OfflineController({OfflineStore? store, DateTime Function()? clock})
      : _store = store ?? MemoryOfflineStore(),
        _clock = clock ?? (() => DateTime.now().toUtc());
  final OfflineStore _store;
  final DateTime Function() _clock;
  OfflineScope? _scope;
  DateTime? _expiresAt;
  Map<String, CachedGet> _cache = {};
  List<OutboxOperation> _operations = [];
  final Map<String, DateTime> _snapshots = {};
  Future<void> _serial = Future.value();
  int _epoch = 0;
  bool _disposed = false;
  bool _offline = false;
  bool _syncing = false;
  String? _storageError;
  bool _storageBlocked = false;

  OfflineScope? get scope => active ? _scope : null;
  int get epoch => _epoch;
  bool get active =>
      !_disposed &&
      _scope != null &&
      _expiresAt != null &&
      _clock().isBefore(_expiresAt!);
  bool get isOffline => _offline;
  bool get usingSnapshot => _snapshots.isNotEmpty;
  DateTime? get snapshotAt => _snapshots.values.isEmpty
      ? null
      : _snapshots.values.reduce((a, b) => a.isBefore(b) ? a : b);
  List<OutboxOperation> get operations => List.unmodifiable(_operations);
  int get pendingCount => _operations
      .where((operation) => operation.status == OutboxStatus.pending)
      .length;
  int get conflictCount => _operations
      .where((operation) => operation.status == OutboxStatus.conflict)
      .length;
  int get errorCount => _operations
      .where((operation) => operation.status == OutboxStatus.error)
      .length;
  bool get syncing => _syncing;
  String? get storageError => _storageError;
  bool current(int epoch) => active && epoch == _epoch;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<T> _transaction<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _serial = _serial.catchError((Object _) {}).then((_) async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<void> flush() => _serial;
  String _encode(
          Map<String, CachedGet> cache, List<OutboxOperation> operations) =>
      jsonEncode({
        'version': 1,
        'scope': _scope!.toJson(),
        'cache': cache.map((key, value) => MapEntry(key, value.toJson())),
        'operations': operations.map((operation) => operation.toJson()).toList()
      });
  Future<void> _save(Map<String, CachedGet> cache,
      List<OutboxOperation> operations, int epoch) async {
    if (!current(epoch)) throw ApiException('La sesión cambió.');
    if (_storageBlocked) {
      throw ApiException(
          'La copia local no se puede leer. Cierra sesión para eliminarla antes de guardar más cambios.');
    }
    if (utf8
            .encode(jsonEncode(
                operations.map((operation) => operation.toJson()).toList()))
            .length >
        8 * 1024 * 1024) {
      throw ApiException(
          'La cola local alcanzó su capacidad. Sincroniza o revisa los cambios pendientes.');
    }
    var encoded = _encode(cache, operations);
    while (utf8.encode(encoded).length > 12 * 1024 * 1024 && cache.isNotEmpty) {
      cache.remove(cache.keys.first);
      encoded = _encode(cache, operations);
    }
    if (utf8.encode(encoded).length > 12 * 1024 * 1024) {
      throw ApiException('El almacenamiento local alcanzó su capacidad.');
    }
    try {
      await _store.write(encoded);
      if (!current(epoch)) throw ApiException('La sesión cambió.');
      _storageError = null;
    } catch (_) {
      if (current(epoch)) {
        _storageError =
            'No se pudo guardar de forma segura en este equipo. No cierres la aplicación con cambios pendientes.';
        _notify();
      }
      rethrow;
    }
  }

  Future<void> activate(OfflineScope scope, DateTime expiresAt) async {
    final epoch = ++_epoch;
    _scope = null;
    _expiresAt = null;
    _cache = {};
    _operations = [];
    _snapshots.clear();
    _offline = false;
    _storageError = null;
    _syncing = false;
    _storageBlocked = false;
    _notify();
    await _transaction(() async {
      if (_disposed || epoch != _epoch) return;
      Map<String, CachedGet> cache = {};
      List<OutboxOperation> operations = [];
      try {
        final persisted = await _store.read();
        if (persisted != null) {
          final json = jsonDecode(persisted) as Map<String, dynamic>;
          final storedScope = OfflineScope.fromJson(
              Map<String, dynamic>.from(json['scope'] as Map));
          if (json['version'] != 1 || storedScope.key != scope.key) {
            await _store.clear();
          } else {
            final storedCache = Map<String, dynamic>.from(json['cache'] as Map);
            for (final entry in storedCache.entries) {
              final value = CachedGet.fromJson(
                  Map<String, dynamic>.from(entry.value as Map));
              if (!safeToPersist(jsonDecode(value.body))) {
                throw const FormatException();
              }
              cache[entry.key] = value;
            }
            operations = (json['operations'] as List)
                .map((item) => OutboxOperation.fromJson(
                    Map<String, dynamic>.from(item as Map)))
                .toList();
            if (cache.length > 80 || operations.length > 100) {
              throw const FormatException();
            }
          }
        }
      } catch (_) {
        if (epoch == _epoch && !_disposed) {
          _storageBlocked = true;
          _storageError =
              'No se pudo abrir la copia local protegida. La sesión necesita datos del servidor.';
        }
        cache = {};
        operations = [];
      }
      if (_disposed || epoch != _epoch) return;
      _scope = scope;
      _expiresAt = expiresAt.toUtc();
      _cache = cache;
      _operations = operations;
      _notify();
    });
  }

  /// Synchronous memory invalidation; durable deletion is serialized after any
  /// write already in progress. A late response cannot recreate the old scope.
  void endSession() {
    _epoch++;
    _scope = null;
    _expiresAt = null;
    _cache = {};
    _operations = [];
    _snapshots.clear();
    _offline = false;
    _syncing = false;
    _storageError = null;
    _storageBlocked = false;
    _notify();
    unawaited(_transaction(() async {
      try {
        await _store.clear();
      } catch (_) {
        if (!_disposed) {
          _storageError = 'No se pudo eliminar la copia local protegida.';
          _notify();
        }
      }
    }));
  }

  void connection(bool available) {
    if (_disposed) return;
    _offline = !available;
    _notify();
  }

  void setSyncing(bool value) {
    if (_disposed) return;
    _syncing = value;
    _notify();
  }

  CachedGet? cached(String key, int epoch) =>
      current(epoch) ? _cache[key] : null;
  void markSnapshot(String key, DateTime at, int epoch) {
    if (!current(epoch)) return;
    _snapshots[key] = at;
    _offline = true;
    _notify();
  }

  Future<void> cacheLive(
      String key, String body, Map<String, String> headers, int epoch) async {
    if (!current(epoch)) return;
    final data = jsonDecode(body);
    if (!safeToPersist(data) || utf8.encode(body).length > 1024 * 1024) return;
    _snapshots.remove(key);
    _offline = false;
    _notify();
    try {
      await _transaction(() async {
        if (!current(epoch)) return;
        final cache = Map<String, CachedGet>.of(_cache)..remove(key);
        cache[key] = CachedGet(
            body: body, headers: Map.unmodifiable(headers), cachedAt: _clock());
        while (cache.length > 80) {
          cache.remove(cache.keys.first);
        }
        await _save(cache, _operations, epoch);
        if (current(epoch)) _cache = cache;
      });
    } catch (_) {/* Online reads remain usable if local storage fails. */}
  }

  Future<void> evict(String key, int epoch) {
    if (current(epoch)) {
      _cache.remove(key);
      _snapshots.remove(key);
      _notify();
    }
    return _transaction(() async {
      if (!current(epoch)) return;
      final cache = Map<String, CachedGet>.of(_cache)..remove(key);
      _snapshots.remove(key);
      await _save(cache, _operations, epoch);
      if (current(epoch)) {
        _cache = cache;
        _notify();
      }
    });
  }

  Future<void> invalidateCache(int epoch) {
    if (current(epoch)) {
      _cache = {};
      _notify();
    }
    return _transaction(() async {
      if (!current(epoch)) return;
      await _save({}, _operations, epoch);
    });
  }

  OutboxOperation? operation(String id) {
    for (final operation in _operations) {
      if (operation.id == id) return operation;
    }
    return null;
  }

  Future<OutboxOperation> enqueue(
      {required String method,
      required String route,
      required Map<String, dynamic> body,
      String? idempotencyKey,
      String? ifMatch}) {
    final epoch = _epoch;
    return _transaction(() async {
      if (!current(epoch) ||
          !safeOfflineMutation(method, route, body, ifMatch)) {
        throw ApiException('Este cambio requiere una conexión activa.');
      }
      if (utf8.encode(jsonEncode(body)).length > 256 * 1024) {
        throw ApiException(
            'El cambio supera el tamaño permitido para guardarlo sin conexión.');
      }
      if (idempotencyKey != null) {
        for (final operation in _operations) {
          if (operation.idempotencyKey == idempotencyKey) {
            if (operation.method != method ||
                operation.route != route ||
                !mapEquals(operation.body, body) ||
                operation.ifMatch != ifMatch) {
              throw ApiException(
                  'La clave del cambio ya corresponde a otros datos.', 409);
            }
            return operation;
          }
        }
      }
      if (_operations.length >= 100) {
        throw ApiException(
            'Sincroniza o revisa los cambios pendientes antes de guardar más.');
      }
      final random = Random.secure();
      final id =
          'cambio-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
      final operation = OutboxOperation(
          id: id,
          method: method,
          route: route,
          body: Map.unmodifiable(Map<String, dynamic>.of(body)),
          idempotencyKey: idempotencyKey ?? id,
          ifMatch: ifMatch,
          createdAt: _clock(),
          status: OutboxStatus.pending,
          attempts: 0);
      final operations = [..._operations, operation];
      await _save(_cache, operations, epoch);
      if (!current(epoch)) throw ApiException('La sesión cambió.');
      _operations = operations;
      _notify();
      return operation;
    });
  }

  Future<void> replace(OutboxOperation operation, int epoch) =>
      _transaction(() async {
        if (!current(epoch)) return;
        final operations = [
          for (final item in _operations)
            if (item.id == operation.id) operation else item
        ];
        await _save(_cache, operations, epoch);
        if (current(epoch)) {
          _operations = operations;
          _notify();
        }
      });
  Future<void> completed(String id, int epoch) => _transaction(() async {
        if (!current(epoch)) return;
        final operations =
            _operations.where((operation) => operation.id != id).toList();
        // A successful mutation invalidates previous snapshots, never fabricates
        // a live resource for an unacknowledged local draft.
        _cache = {};
        await _save({}, operations, epoch);
        if (current(epoch)) {
          _operations = operations;
          _cache = {};
          _notify();
        }
      });
  Future<void> descartar(String id) {
    final epoch = _epoch;
    return _transaction(() async {
      if (!current(epoch)) return;
      final operations =
          _operations.where((operation) => operation.id != id).toList();
      await _save(_cache, operations, epoch);
      if (current(epoch)) {
        _operations = operations;
        _notify();
      }
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _scope = null;
    _expiresAt = null;
    _cache = {};
    _operations = [];
    _snapshots.clear();
    // App shutdown preserves encrypted pending work. Explicit logout calls
    // endSession before this method and queues durable deletion instead.
    super.dispose();
  }
}
