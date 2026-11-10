import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../services/api_client.dart';

/// La sesión y su token viven únicamente en memoria.
class SesionProvider extends ChangeNotifier {
  SesionProvider(this.api) {
    api.onUnauthorized = expirar;
  }

  final ApiClient api;
  Map<String, dynamic>? _usuario;
  Timer? _temporizador;
  Timer? _reintento;
  int _esperaAutenticacion = 0;
  DateTime? _vence;
  int _version = 0;
  bool _ocupado = false;
  bool _disposed = false;
  bool _guardandoPerfil = false;
  int _solicitudPerfil = 0;
  String? mensaje;

  Map<String, dynamic>? get usuario => _usuario;
  bool get autenticado => _usuario != null;
  bool get ocupado => _ocupado || _esperaAutenticacion > 0;
  int get esperaAutenticacion => _esperaAutenticacion;

  Future<dynamic> _solicitarAutenticacion(
      String ruta, Map<String, dynamic> datos) async {
    if (_esperaAutenticacion > 0) {
      throw ApiException(
          'Espera $_esperaAutenticacion segundos para reintentar.',
          429,
          Duration(seconds: _esperaAutenticacion));
    }
    try {
      return await api.post(ruta, datos);
    } on ApiException catch (error) {
      if (error.status == 429 && !_disposed) {
        final delay = error.retryAfter ?? const Duration(seconds: 60);
        _esperaAutenticacion = (delay.inMilliseconds / 1000).ceil();
        _reintento?.cancel();
        if (_esperaAutenticacion > 0) {
          _reintento = Timer.periodic(const Duration(seconds: 1), (timer) {
            _esperaAutenticacion--;
            if (_esperaAutenticacion <= 0) timer.cancel();
            if (!_disposed) notifyListeners();
          });
        }
        notifyListeners();
      }
      rethrow;
    }
  }

  int get version => _version;
  bool get guardandoPerfil => _guardandoPerfil;

  Future<void> ingresar(String correo, String password) async {
    if (_ocupado) return;
    final versionInicial = _version;
    _ocupado = true;
    mensaje = null;
    notifyListeners();
    try {
      final datos = await _solicitarAutenticacion('/api/auth/login', {
        'correo': correo.trim(),
        'password': password,
      });
      if (_disposed || versionInicial != _version) return;
      if (datos is! Map ||
          datos['access_token'] is! String ||
          (datos['access_token'] as String).isEmpty ||
          datos['token_type'] != 'Bearer' ||
          datos['expires_in'] is! int ||
          (datos['expires_in'] as int) <= 0 ||
          datos['usuario'] is! Map) {
        throw ApiException('Respuesta de inicio de sesión inválida.');
      }
      final perfil = Map<String, dynamic>.from(datos['usuario'] as Map);
      if (perfil['id'] is! String ||
          perfil['nombre'] is! String ||
          perfil['correo'] is! String ||
          perfil['rol'] is! String ||
          perfil['estado'] != 'activo') {
        throw ApiException('El servidor no devolvió una cuenta activa válida.');
      }
      final vence = DateTime.now()
          .toUtc()
          .add(Duration(seconds: datos['expires_in'] as int));
      await api.iniciarSesionOffline(
          userId: perfil['id'] as String,
          role: perfil['rol'] as String,
          expiresAt: vence);
      if (_disposed || versionInicial != _version) return;
      api.token = datos['access_token'] as String;
      _vence = vence;
      _usuario = Map.unmodifiable(perfil);
      _version++;
      _temporizador?.cancel();
      _temporizador = Timer(vence.difference(DateTime.now().toUtc()), expirar);
    } finally {
      if (!_disposed) {
        _ocupado = false;
        notifyListeners();
      }
    }
  }

  Future<void> registrar(Map<String, String> datos) async {
    await _solicitarAutenticacion('/api/auth/register', datos);
  }

  Future<void> actualizarPerfil(String nombre) async {
    if (_disposed || !autenticado) return;
    if (_guardandoPerfil) {
      throw ApiException(
          'Ya se está guardando tu perfil. Espera a que termine antes de volver a intentarlo.');
    }
    final limpio = nombre.trim();
    if (limpio.isEmpty || limpio.length > 250) {
      throw ApiException('Escribe un nombre de entre 1 y 250 caracteres.');
    }
    final solicitud = ++_solicitudPerfil;
    final versionInicial = _version;
    final id = _usuario!['id'];
    final token = api.token;
    _guardandoPerfil = true;
    notifyListeners();
    try {
      final respuesta = await api.put('/api/usuarios/me', {'nombre': limpio});
      if (_disposed ||
          solicitud != _solicitudPerfil ||
          _version != versionInicial ||
          api.token != token ||
          _usuario?['id'] != id) {
        return;
      }
      if (respuesta is! Map<String, dynamic> ||
          respuesta['id'] != id ||
          respuesta['nombre'] is! String ||
          (respuesta['nombre'] as String).trim().isEmpty ||
          respuesta['correo'] != _usuario!['correo'] ||
          !const ['pyme', 'inversionista', 'administrador']
              .contains(respuesta['rol']) ||
          respuesta['estado'] != 'activo') {
        throw ApiException('El servidor devolvió un perfil inválido.');
      }
      // El nombre conserva la navegación; un cambio de rol invalida datos y
      // rutas que pudieron haberse cargado con los permisos anteriores.
      if (respuesta['rol'] != _usuario!['rol']) {
        api.offline.endSession();
        await api.iniciarSesionOffline(
            userId: id as String,
            role: respuesta['rol'] as String,
            expiresAt: _vence ?? DateTime.now().toUtc());
        if (_disposed ||
            solicitud != _solicitudPerfil ||
            _version != versionInicial ||
            api.token != token ||
            _usuario?['id'] != id) {
          return;
        }
        _version++;
      }
      _usuario = Map.unmodifiable(respuesta);
    } catch (_) {
      if (_disposed ||
          solicitud != _solicitudPerfil ||
          _version != versionInicial ||
          api.token != token ||
          _usuario?['id'] != id) {
        return;
      }
      rethrow;
    } finally {
      if (!_disposed && solicitud == _solicitudPerfil) {
        _guardandoPerfil = false;
        notifyListeners();
      }
    }
  }

  void expirar() {
    if (!autenticado || _disposed) return;
    cerrar(motivo: 'Tu sesión terminó. Inicia sesión nuevamente.');
  }

  void cerrar({String? motivo}) {
    _temporizador?.cancel();
    _vence = null;
    api.terminarSesionOffline();
    _usuario = null;
    mensaje = motivo;
    _version++;
    _solicitudPerfil++;
    _guardandoPerfil = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _reintento?.cancel();
    _temporizador?.cancel();
    api.onUnauthorized = null;
    _vence = null;
    api.close();
    super.dispose();
  }
}
