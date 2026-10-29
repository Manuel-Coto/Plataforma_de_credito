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
  int _version = 0;
  bool _ocupado = false;
  bool _disposed = false;
  String? mensaje;

  Map<String, dynamic>? get usuario => _usuario;
  bool get autenticado => _usuario != null;
  bool get ocupado => _ocupado;
  int get version => _version;

  Future<void> ingresar(String correo, String password) async {
    if (_ocupado) return;
    final versionInicial = _version;
    _ocupado = true;
    mensaje = null;
    notifyListeners();
    try {
      final datos = await api.post('/api/auth/login', {
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
      api.token = datos['access_token'] as String;
      _usuario = Map.unmodifiable(perfil);
      _version++;
      _temporizador?.cancel();
      _temporizador =
          Timer(Duration(seconds: datos['expires_in'] as int), expirar);
    } finally {
      if (!_disposed) {
        _ocupado = false;
        notifyListeners();
      }
    }
  }

  Future<void> registrar(Map<String, String> datos) async {
    await api.post('/api/auth/register', datos);
  }

  void expirar() {
    if (!autenticado || _disposed) return;
    cerrar(motivo: 'Tu sesión terminó. Inicia sesión nuevamente.');
  }

  void cerrar({String? motivo}) {
    _temporizador?.cancel();
    api.token = null;
    _usuario = null;
    mensaje = motivo;
    _version++;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _temporizador?.cancel();
    api.onUnauthorized = null;
    api.token = null;
    api.close();
    super.dispose();
  }
}
