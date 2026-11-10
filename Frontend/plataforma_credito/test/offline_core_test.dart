import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plataforma_credito/services/api_client.dart';

const _company = <String, dynamic>{
  'nombre': 'Empresa ficticia',
  'nit': '123456789',
  'correo': 'prueba@example.test',
  'telefono': '22223333',
  'direccion': 'Dirección ficticia'
};
http.Response _json(Object value,
        [int status = 200, Map<String, String> headers = const {}]) =>
    http.Response(jsonEncode(value), status, headers: {
      'content-type': 'application/json; charset=utf-8',
      ...headers
    });
http.Response _profile([String role = 'pyme']) =>
    _json({'id': 'user-1', 'rol': role, 'estado': 'activo'});
Future<ApiClient> _open(Future<http.Response> Function(http.Request) handler,
    {OfflineStore? store,
    String role = 'pyme',
    String user = 'user-1',
    String base = 'http://example.test'}) async {
  final api = ApiClient(
      httpClient: MockClient(handler), baseUrl: base, offlineStore: store);
  await api.iniciarSesionOffline(
      userId: user,
      role: role,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)));
  api.token = 'token-ficticio-no-persistir';
  return api;
}

class _FailingStore extends MemoryOfflineStore {
  bool fail = false;
  @override
  Future<void> write(String contents) async {
    if (fail) throw const FileSystemException('Fallo simulado');
    await super.write(contents);
  }
}

void main() {
  test(
      'GET protegido usa snapshot solo por transporte/503, conserva ETag y fecha',
      () async {
    var mode = 200;
    final api = await _open((request) async {
      if (mode == -1) throw http.ClientException('transporte simulado');
      return mode == 200
          ? _json({'id': 'empresa-1'}, 200, {'etag': '"1-test"'})
          : _json({'error': 'no disponible'}, mode);
    });
    addTearDown(api.close);
    expect(await api.get('/api/empresas/empresa-1'), {'id': 'empresa-1'});
    mode = -1;
    final snapshot = await api.getConCabeceras('/api/empresas/empresa-1');
    expect(snapshot.headers['etag'], '"1-test"');
    expect(snapshot.headers['x-offline-snapshot'], 'true');
    expect(api.offline.usingSnapshot, isTrue);
    expect(api.offline.snapshotAt, isNotNull);
    mode = 503;
    expect(await api.get('/api/empresas/empresa-1'), {'id': 'empresa-1'});
  });

  test('JSON inválido y 401/403 nunca se convierten en snapshot', () async {
    for (final failure in [200, 401, 403]) {
      var first = true;
      final api = await _open((request) async {
        if (request.url.path == '/api/usuarios/me') return _profile();
        if (first) {
          first = false;
          return _json({'id': 'empresa-1'});
        }
        return failure == 200
            ? http.Response('{malformado', 200)
            : _json({'error': 'denegado'}, failure);
      });
      await api.get('/api/empresas/empresa-1');
      await expectLater(
          api.get('/api/empresas/empresa-1'),
          failure == 200
              ? throwsFormatException
              : throwsA(isA<ApiException>()
                  .having((error) => error.status, 'HTTP', failure)));
      expect(api.offline.usingSnapshot, isFalse);
      if (failure == 401) {
        expect(api.token, isNull);
        expect(api.offline.active, isFalse);
      }
      api.close();
    }
  });

  test('caché persistida queda aislada por usuario, rol y servidor', () async {
    final store = MemoryOfflineStore();
    final original = await _open((_) async => _json({'privado': 'cuenta uno'}),
        store: store);
    await original.get('/api/empresas');
    final contents = store.contents;
    original.close();
    for (final scope in [
      (user: 'user-2', role: 'pyme', base: 'http://example.test'),
      (user: 'user-1', role: 'administrador', base: 'http://example.test'),
      (user: 'user-1', role: 'pyme', base: 'http://otro.test')
    ]) {
      final separate = MemoryOfflineStore()..contents = contents;
      final api = await _open(
          (_) async => throw http.ClientException('sin red'),
          store: separate,
          user: scope.user,
          role: scope.role,
          base: scope.base);
      await expectLater(api.get('/api/empresas'), throwsA(isA<ApiException>()));
      expect(api.offline.usingSnapshot, isFalse);
      expect(separate.contents, isNull);
      api.close();
    }
  });

  test(
      'expiración impide leer copias aunque el temporizador aún no haya corrido',
      () async {
    var now = DateTime.utc(2026, 11, 8);
    final offline = OfflineController(clock: () => now);
    final api = ApiClient(
        baseUrl: 'http://example.test',
        offlineController: offline,
        httpClient:
            MockClient((_) async => throw http.ClientException('sin red')));
    addTearDown(api.close);
    await offline.activate(
        OfflineScope(baseUrl: api.baseUrl, userId: 'user-1', role: 'pyme'),
        now.add(const Duration(seconds: 5)));
    api.token = 'token-ficticio';
    await offline.cacheLive('${api.baseUrl}/api/empresas',
        jsonEncode({'empresas': []}), {}, offline.epoch);
    now = now.add(const Duration(seconds: 6));
    await expectLater(api.get('/api/empresas'), throwsA(isA<ApiException>()));
    expect(offline.active, isFalse);
  });

  test(
      'outbox se guarda antes del POST y reabre sin JWT con la misma clave y cuerpo',
      () async {
    final store = MemoryOfflineStore();
    String? key;
    final first = await _open((request) async {
      key = request.headers['Idempotency-Key'];
      expect(key, isNotEmpty);
      expect(store.contents, contains(key));
      return _json({'error': 'sin servicio'}, 503);
    }, store: store);
    await expectLater(first.post('/api/empresas', _company),
        throwsA(isA<OfflineQueuedException>()));
    final operation = first.offline.operations.single;
    expect(operation.attempts, 1);
    expect(store.contents, isNot(contains('token-ficticio-no-persistir')));
    expect(store.contents, isNot(contains('Authorization')));
    expect(store.contents, isNot(contains('access_token')));
    first.close();
    var posts = 0;
    final restored = await _open((request) async {
      if (request.method == 'GET') return _profile();
      posts++;
      expect(request.headers['Idempotency-Key'], key);
      expect(jsonDecode(request.body), _company);
      return _json({'id': 'empresa-creada'});
    }, store: store);
    addTearDown(restored.close);
    expect(restored.offline.operations.single.id, operation.id);
    final result = await restored.sincronizarPendientes();
    expect(result.sent, 1);
    expect(posts, 1);
    expect(restored.offline.operations, isEmpty);
  });

  test(
      'tres intentos automáticos máximo y reintento explícito conserva identidad',
      () async {
    var online = false;
    final keys = <String?>[];
    final api = await _open((request) async {
      if (request.method == 'GET') return _profile();
      keys.add(request.headers['Idempotency-Key']);
      return online ? _json({'id': 'empresa'}) : _json({'error': 'caído'}, 503);
    });
    addTearDown(api.close);
    await expectLater(api.post('/api/empresas', _company),
        throwsA(isA<OfflineQueuedException>()));
    final id = api.offline.operations.single.id;
    await api.sincronizarPendientes();
    await api.sincronizarPendientes();
    await api.sincronizarPendientes();
    expect(keys, hasLength(3));
    expect(api.offline.operations.single.attempts, 3);
    expect(api.offline.operations.single.status, OutboxStatus.error);
    online = true;
    await api.reintentarOperacion(id);
    expect(keys.toSet(), hasLength(1));
    expect(api.offline.operations, isEmpty);
  });

  test('finanzas, permisos, DTE y PUT sin revisión nunca entran en la cola',
      () async {
    final api = await _open((_) async => _json({'error': 'caído'}, 503));
    addTearDown(api.close);
    for (final route in [
      '/api/inversiones',
      '/api/ofertas',
      '/api/creditos',
      '/api/creditos/credito/pagos',
      '/api/usuarios'
    ]) {
      await expectLater(
          api.post(route, {'monto': 10}),
          throwsA(isA<ApiException>().having(
              (error) => error is OfflineQueuedException,
              'encolado',
              isFalse)));
    }
    await expectLater(
        api.patch('/api/facturas/factura/verificar-dte',
            {'sello_recepcion': 'ficticio'}),
        throwsA(isA<ApiException>()));
    await expectLater(api.put('/api/empresas/empresa-1', _company),
        throwsA(isA<ApiException>()));
    expect(api.offline.operations, isEmpty);
  });

  test('403 revalida rol remoto y purga también snapshots de otras rutas',
      () async {
    var revoked = false;
    final api = await _open((request) async {
      if (request.url.path == '/api/usuarios/me') return _profile('pyme');
      if (!revoked) return _json({'privado': 'administración'});
      return _json({'error': 'denegado'},
          request.url.path.endsWith('resumen') ? 403 : 503);
    }, role: 'administrador');
    addTearDown(api.close);
    await api.get('/api/administracion/resumen');
    await api.get('/api/usuarios');
    revoked = true;
    await expectLater(
        api.get('/api/administracion/resumen'), throwsA(isA<ApiException>()));
    expect(api.token, isNull);
    expect(api.offline.active, isFalse);
    await expectLater(api.get('/api/usuarios'), throwsA(isA<ApiException>()));
    expect(api.offline.usingSnapshot, isFalse);
  });

  test('nuevo login válido restaura fallback tras revocación 403 previa',
      () async {
    var mode = 0;
    final api = await _open((request) async {
      if (request.url.path == '/api/usuarios/me') return _profile('pyme');
      if (mode == 1) return _json({'error': 'denegado'}, 403);
      if (mode == 3) return _json({'error': 'sin servicio'}, 503);
      return _json({'id': 'empresa-nueva-sesion'});
    }, role: 'administrador');
    addTearDown(api.close);
    await api.get('/api/empresas/empresa-1');
    mode = 1;
    await expectLater(
        api.get('/api/empresas/empresa-1'), throwsA(isA<ApiException>()));
    expect(api.token, isNull);
    await api.iniciarSesionOffline(
        userId: 'user-1',
        role: 'pyme',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)));
    api.token = 'token-ficticio-nueva-sesion';
    mode = 2;
    await api.get('/api/empresas/empresa-1');
    mode = 3;
    expect(await api.get('/api/empresas/empresa-1'),
        {'id': 'empresa-nueva-sesion'});
    expect(api.offline.usingSnapshot, isTrue);
  });

  test('evicción 403 permanece en memoria aunque falle el disco', () async {
    final store = _FailingStore();
    var status = 200;
    final api = await _open((request) async {
      if (request.url.path == '/api/usuarios/me') return _profile();
      return _json({'id': 'empresa-1'}, status);
    }, store: store);
    addTearDown(api.close);
    await api.get('/api/empresas/empresa-1');
    store.fail = true;
    status = 403;
    await expectLater(
        api.get('/api/empresas/empresa-1'),
        throwsA(
            isA<ApiException>().having((error) => error.status, 'HTTP', 403)));
    status = 503;
    await expectLater(
        api.get('/api/empresas/empresa-1'), throwsA(isA<ApiException>()));
    expect(api.offline.usingSnapshot, isFalse);
  });

  test('dos reintentos del mismo ID comparten un solo envío', () async {
    var first = true;
    var writes = 0;
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final api = await _open((request) async {
      if (request.method == 'GET') return _profile();
      writes++;
      if (first) {
        first = false;
        return _json({'error': 'caído'}, 503);
      }
      if (!started.isCompleted) started.complete();
      return response.future;
    });
    addTearDown(api.close);
    await expectLater(api.post('/api/empresas', _company),
        throwsA(isA<OfflineQueuedException>()));
    final id = api.offline.operations.single.id;
    final a = api.reintentarOperacion(id);
    final b = api.reintentarOperacion(id);
    await started.future;
    expect(writes, 2);
    response.complete(_json({'id': 'empresa'}));
    await Future.wait([a, b]);
    expect(writes, 2);
    expect(api.offline.operations, isEmpty);
  });

  test('sincronización y envío inicial del mismo ID no compiten', () async {
    var writes = 0;
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final api = await _open((request) async {
      if (request.method == 'GET') return _profile();
      writes++;
      started.complete();
      return response.future;
    });
    addTearDown(api.close);
    final initial = api.post('/api/empresas', _company);
    await started.future;
    final sync = api.sincronizarPendientes();
    await Future<void>.delayed(Duration.zero);
    response.complete(_json({'id': 'empresa'}));
    await Future.wait<dynamic>([initial, sync]);
    expect(writes, 1);
    expect(api.offline.operations, isEmpty);
  });

  test('logout purga pendientes y una respuesta tardía no los revive',
      () async {
    final store = MemoryOfflineStore();
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final api = await _open((_) async {
      started.complete();
      return response.future;
    }, store: store);
    addTearDown(api.close);
    final pending = api.post('/api/empresas', _company);
    final rejected = expectLater(pending, throwsA(isA<ApiException>()));
    await started.future;
    api.terminarSesionOffline();
    response.complete(_json({'id': 'empresa'}));
    await rejected;
    await api.offline.flush();
    expect(api.offline.operations, isEmpty);
    expect(api.offline.active, isFalse);
    expect(store.contents, isNull);
  });

  test('presupuesto total evicta caché antes de perder un pendiente durable',
      () async {
    final store = MemoryOfflineStore();
    final offline = OfflineController(store: store);
    final scope = OfflineScope(
        baseUrl: 'http://example.test', userId: 'user-1', role: 'pyme');
    await offline.activate(
        scope, DateTime.now().toUtc().add(const Duration(hours: 1)));
    await offline.enqueue(
        method: 'POST', route: '/api/empresas', body: _company);
    for (var i = 0; i < 15; i++) {
      await offline.cacheLive(
          'pagina-$i',
          jsonEncode({'datos': List.filled(900000, 'x').join()}),
          {},
          offline.epoch);
    }
    expect(utf8.encode(store.contents!).length,
        lessThanOrEqualTo(12 * 1024 * 1024));
    expect(offline.operations, hasLength(1));
    offline.dispose();
    final restored = OfflineController(store: store);
    addTearDown(restored.dispose);
    await restored.activate(
        scope, DateTime.now().toUtc().add(const Duration(hours: 1)));
    expect(restored.operations, hasLength(1));
    expect(restored.storageError, isNull);
    await expectLater(
        restored.enqueue(
            method: 'POST',
            route: '/api/empresas',
            body: {..._company, 'direccion': List.filled(270000, 'x').join()}),
        throwsA(isA<ApiException>()));
    expect(restored.operations, hasLength(1));
  });

  test('DPAPI real: cargas desde 1 KiB hasta el presupuesto de 12 MiB',
      () async {
    if (!Platform.isWindows) return;
    final cipher = WindowsDpapiCipher();
    for (final size in [1024, 100 * 1024, 1024 * 1024, 12 * 1024 * 1024]) {
      final plain = Uint8List(size);
      for (var index = 0; index < size; index++) {
        plain[index] = (index * 31 + 7) & 255;
      }
      final encrypted = await cipher.protect(plain);
      expect(await cipher.unprotect(encrypted), orderedEquals(plain));
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('DPAPI nativo conserva compatibilidad con archivos de PowerShell',
      () async {
    if (!Platform.isWindows) return;
    final windows = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final executable =
        '$windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
    final cipher = WindowsDpapiCipher();
    final plain = Uint8List.fromList(
        utf8.encode('fixture-offline-compatibilidad-sin-credenciales'));
    final native = await cipher.protect(plain);
    // Only this synthetic fixture travels in the test command. Production
    // calls use the native API and never put application data in argv.
    final script = '\$ErrorActionPreference="Stop"; '
        'Add-Type -AssemblyName System.Security; '
        '\$entropy=[Text.Encoding]::UTF8.GetBytes("PlataformaCredito.offline.v1"); '
        '\$scope=[Security.Cryptography.DataProtectionScope]::CurrentUser; '
        '\$native=[Convert]::FromBase64String("${base64Encode(native)}"); '
        '\$plain=[Security.Cryptography.ProtectedData]::Unprotect(\$native,\$entropy,\$scope); '
        '\$legacy=[Security.Cryptography.ProtectedData]::Protect(\$plain,\$entropy,\$scope); '
        '[Console]::Out.Write([Convert]::ToBase64String(\$plain)+":"+[Convert]::ToBase64String(\$legacy))';
    final result = await Process.run(executable,
            ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', script],
            runInShell: false)
        .timeout(const Duration(seconds: 20));
    expect(result.exitCode, 0, reason: 'Compatibilidad DPAPI con PowerShell');
    final output = (result.stdout as String).trim().split(':');
    expect(output, hasLength(2));
    expect(base64Decode(output[0]), orderedEquals(plain));
    expect(
        await cipher.unprotect(base64Decode(output[1])), orderedEquals(plain));
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('DPAPI real: archivo cifrado, reapertura y sustitución sin texto plano',
      () async {
    if (!Platform.isWindows) return;
    final directory =
        await Directory.systemTemp.createTemp('credito-offline-contract-');
    final store = EncryptedFileOfflineStore(
        directory: directory, cipher: WindowsDpapiCipher());
    const plain = 'fixture-offline-sintetica-sin-credenciales-2026';
    try {
      await store.write(jsonEncode({'datos': plain}));
      final files =
          await directory.list().where((entry) => entry is File).toList();
      expect(files, hasLength(1));
      final bytes = await File(files.single.path).readAsBytes();
      expect(latin1.decode(bytes), isNot(contains(plain)));
      final reopened = EncryptedFileOfflineStore(
          directory: directory, cipher: WindowsDpapiCipher());
      expect(jsonDecode((await reopened.read())!)['datos'], plain);
      await reopened.write(jsonEncode({'datos': 'segunda versión ficticia'}));
      expect(jsonDecode((await store.read())!)['datos'],
          'segunda versión ficticia');
    } finally {
      await store.clear();
      await directory.delete();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
