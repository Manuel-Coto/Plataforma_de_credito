import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/credito_theme.dart';
import '../../../services/api_client.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/page_header.dart';
import '../../../widgets/vista_error.dart';
import '../providers/sesion_provider.dart';

class UsuariosGestionScreen extends StatefulWidget {
  const UsuariosGestionScreen({super.key});

  @override
  State<UsuariosGestionScreen> createState() => _UsuariosGestionScreenState();
}

class _UsuariosGestionScreenState extends State<UsuariosGestionScreen> {
  final _usuarios = <_UsuarioGestion>[];
  final _cursores = <String>{};
  String? _bookmark;
  String? _error;
  bool _cargando = false;
  bool _hayMas = true;
  int _solicitud = 0;

  bool get _admin =>
      context.read<SesionProvider>().usuario?['rol'] == 'administrador';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _admin) _cargar();
    });
  }

  @override
  void dispose() {
    _solicitud++;
    super.dispose();
  }

  Future<void> _cargar({bool mas = false}) async {
    if (!mounted || !_admin || (mas && (_cargando || !_hayMas))) return;
    final solicitud = ++_solicitud;
    final sesion = context.read<SesionProvider>();
    final version = sesion.version;
    var cursor = mas ? _bookmark : null;
    setState(() {
      _cargando = true;
      _error = null;
      if (!mas) {
        _usuarios.clear();
        _bookmark = null;
        _hayMas = true;
        _cursores.clear();
      }
    });
    try {
      final cursores = <String>{..._cursores};
      while (true) {
        final respuesta = await sesion.api.get('/api/usuarios', query: {
          'limit': '25',
          if (cursor != null) 'bookmark': cursor,
        });
        if (!mounted || solicitud != _solicitud || sesion.version != version) {
          return;
        }
        if (respuesta is! Map<String, dynamic> ||
            respuesta['usuarios'] is! List ||
            respuesta['bookmark'] is! String ||
            respuesta['limit'] is! int ||
            (respuesta['limit'] as int) < 1 ||
            (respuesta['limit'] as int) > 100) {
          throw const FormatException('Página de usuarios inválida');
        }
        final usuarios = (respuesta['usuarios'] as List).map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('Usuario inválido');
          }
          return _UsuarioGestion.fromJson(item);
        }).toList();
        final bookmark = respuesta['bookmark'] as String;
        final avanza = bookmark.isNotEmpty && cursores.add(bookmark);
        if (usuarios.isEmpty && avanza) {
          cursor = bookmark;
          continue;
        }
        setState(() {
          for (final usuario in usuarios) {
            final index = _usuarios.indexWhere((u) => u.id == usuario.id);
            if (index < 0) {
              _usuarios.add(usuario);
            } else {
              _usuarios[index] = usuario;
            }
          }
          _bookmark = bookmark;
          _hayMas = avanza;
          _cursores
            ..clear()
            ..addAll(cursores);
        });
        break;
      }
    } on ApiException catch (error) {
      if (mounted && solicitud == _solicitud && sesion.version == version) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted && solicitud == _solicitud && sesion.version == version) {
        setState(
            () => _error = 'No pudimos leer los usuarios. Intenta nuevamente.');
      }
    } finally {
      if (mounted && solicitud == _solicitud && sesion.version == version) {
        setState(() => _cargando = false);
      }
    }
  }

  Future<void> _abrir(_UsuarioGestion usuario) async {
    final actualizado = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PermisosDialog(id: usuario.id));
    if (mounted && actualizado == true) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permisos actualizados.')));
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sesion = context.watch<SesionProvider>();
    if (sesion.usuario?['rol'] != 'administrador') {
      return const EmptyState(
          icon: Icons.lock_outline,
          title: 'Acceso reservado',
          message:
              'Solo una cuenta administradora puede gestionar usuarios y permisos.');
    }
    return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Column(children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  child: PageHeader(
                      eyebrow: 'ADMINISTRACIÓN',
                      title: 'Usuarios y permisos',
                      subtitle:
                          'Consulta las cuentas y administra su rol y estado.',
                      action: OutlinedButton.icon(
                          onPressed: _cargando ? null : _cargar,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Actualizar')))),
              Expanded(child: _contenido()),
            ])));
  }

  Widget _contenido() {
    if (_cargando && _usuarios.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _usuarios.isEmpty) {
      return VistaError(mensaje: _error!, onReintentar: _cargar);
    }
    if (_usuarios.isEmpty) {
      return const EmptyState(
          icon: Icons.people_outline,
          title: 'Sin usuarios para mostrar',
          message: 'Las cuentas registradas aparecerán aquí.');
    }
    return ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        children: [
          for (final usuario in _usuarios)
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                    child: InkWell(
                        onTap: () => _abrir(usuario),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const CircleAvatar(
                                      backgroundColor: AppColors.softPrimary,
                                      child: Icon(Icons.person_outline,
                                          color: AppColors.primary)),
                                  const SizedBox(width: 14),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(usuario.nombre,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium),
                                        const SizedBox(height: 5),
                                        Text(usuario.correo,
                                            style: const TextStyle(
                                                color: AppColors.muted)),
                                        const SizedBox(height: 10),
                                        Wrap(
                                            spacing: 12,
                                            runSpacing: 6,
                                            children: [
                                              Text(_rolLabel(usuario.rol),
                                                  style: const TextStyle(
                                                      color:
                                                          AppColors.primary)),
                                              Text(
                                                  usuario.estado == 'activo'
                                                      ? 'Activo'
                                                      : 'Inactivo',
                                                  style: TextStyle(
                                                      color: usuario.estado ==
                                                              'activo'
                                                          ? AppColors.primary
                                                          : AppColors.error)),
                                            ]),
                                      ])),
                                  const Icon(Icons.chevron_right_rounded,
                                      color: AppColors.muted),
                                ]))))),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.error))),
          if (_hayMas)
            Center(
                child: OutlinedButton.icon(
                    onPressed: _cargando ? null : () => _cargar(mas: true),
                    icon: const Icon(Icons.expand_more_rounded),
                    label: Text(_cargando
                        ? 'Cargando...'
                        : _error == null
                            ? 'Cargar más usuarios'
                            : 'Reintentar página'))),
        ]);
  }
}

class _UsuarioGestion {
  const _UsuarioGestion(
      this.id, this.nombre, this.correo, this.rol, this.estado);
  final String id, nombre, correo, rol, estado;

  factory _UsuarioGestion.fromJson(Map<String, dynamic> json) {
    for (final campo in ['id', 'nombre', 'correo', 'rol', 'estado']) {
      if (json[campo] is! String || (json[campo] as String).trim().isEmpty) {
        throw const FormatException('Perfil de usuario incompatible');
      }
    }
    if (!const ['pyme', 'inversionista', 'administrador']
            .contains(json['rol']) ||
        !const ['activo', 'inactivo'].contains(json['estado'])) {
      throw const FormatException('Permisos de usuario incompatibles');
    }
    return _UsuarioGestion(json['id'], json['nombre'], json['correo'],
        json['rol'], json['estado']);
  }
}

String _rolLabel(String rol) => switch (rol) {
      'pyme' => 'PYME',
      'inversionista' => 'Inversionista',
      'administrador' => 'Administrador',
      _ => rol,
    };

class _PermisosDialog extends StatefulWidget {
  const _PermisosDialog({required this.id});
  final String id;
  @override
  State<_PermisosDialog> createState() => _PermisosDialogState();
}

class _PermisosDialogState extends State<_PermisosDialog> {
  _UsuarioGestion? _usuario;
  String? _etag, _rol, _estado, _error;
  bool _cargando = true, _guardando = false, _conflicto = false;
  int _solicitud = 0;
  String get _ruta => '/api/usuarios/${Uri.encodeComponent(widget.id)}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _leer();
    });
  }

  @override
  void dispose() {
    _solicitud++;
    super.dispose();
  }

  Future<void> _leer() async {
    final solicitud = ++_solicitud;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final respuesta =
          await context.read<SesionProvider>().api.getConCabeceras(_ruta);
      if (!mounted || solicitud != _solicitud) return;
      final json = jsonDecode(utf8.decode(respuesta.bodyBytes));
      final etag = respuesta.headers['etag'];
      if (json is! Map<String, dynamic> ||
          etag == null ||
          !RegExp(r'^"[A-Za-z0-9-]+"$').hasMatch(etag)) {
        throw const FormatException('Falta la revisión del usuario');
      }
      final usuario = _UsuarioGestion.fromJson(json);
      if (usuario.id != widget.id) {
        throw const FormatException('Usuario distinto');
      }
      setState(() {
        _usuario = usuario;
        _etag = etag;
        _rol = usuario.rol;
        _estado = usuario.estado;
        _conflicto = false;
      });
    } on ApiException catch (error) {
      if (mounted && solicitud == _solicitud) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted && solicitud == _solicitud) {
        setState(() => _error =
            'No se pudo leer el usuario y su revisión. Intenta actualizar.');
      }
    } finally {
      if (mounted && solicitud == _solicitud) setState(() => _cargando = false);
    }
  }

  Future<void> _guardar() async {
    if (_guardando || _conflicto || _usuario == null || _etag == null) return;
    setState(() => _guardando = true);
    final confirmar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Confirmar permisos'),
                content: Text(
                    'La cuenta de ${_usuario!.nombre} tendrá el rol ${_rolLabel(_rol!)} y estado ${_estado == 'activo' ? 'Activo' : 'Inactivo'}. ¿Deseas guardar estos cambios?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Confirmar cambios'))
                ]));
    if (!mounted) return;
    if (confirmar != true) {
      setState(() => _guardando = false);
      return;
    }
    try {
      await context
          .read<SesionProvider>()
          .api
          .patch(_ruta, {'rol': _rol!, 'estado': _estado!}, ifMatch: _etag!);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _conflicto = error.status == 409 || error.status == 412;
          _error = _conflicto
              ? 'Este usuario cambió mientras lo revisabas. Actualiza sus datos antes de guardar nuevamente.'
              : error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'No se pudieron guardar los permisos. Intenta nuevamente.');
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final propio = context.watch<SesionProvider>().usuario?['id'] == widget.id;
    final usuario = _usuario;
    final sinCambios =
        usuario == null || (_rol == usuario.rol && _estado == usuario.estado);
    return AlertDialog(
      scrollable: true,
      title: const Text('Permisos de usuario'),
      content: SizedBox(
          width: 480,
          child: _cargando
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                      if (usuario != null) ...[
                        Text(usuario.nombre,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Text(usuario.correo,
                            style: const TextStyle(color: AppColors.muted)),
                        const SizedBox(height: 24),
                        DropdownButtonFormField<String>(
                            isExpanded: true,
                            key: ValueKey('rol-$_rol-$_solicitud'),
                            initialValue: _rol,
                            decoration: const InputDecoration(labelText: 'Rol'),
                            items: [
                              for (final rol in [
                                'pyme',
                                'inversionista',
                                'administrador'
                              ])
                                DropdownMenuItem(
                                    value: rol, child: Text(_rolLabel(rol)))
                            ],
                            onChanged: propio || _guardando || _conflicto
                                ? null
                                : (value) => setState(() => _rol = value)),
                        const SizedBox(height: 18),
                        DropdownButtonFormField<String>(
                            isExpanded: true,
                            key: ValueKey('estado-$_estado-$_solicitud'),
                            initialValue: _estado,
                            decoration:
                                const InputDecoration(labelText: 'Estado'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'activo', child: Text('Activo')),
                              DropdownMenuItem(
                                  value: 'inactivo', child: Text('Inactivo'))
                            ],
                            onChanged: propio || _guardando || _conflicto
                                ? null
                                : (value) => setState(() => _estado = value)),
                        if (propio)
                          const Padding(
                              padding: EdgeInsets.only(top: 16),
                              child: Text(
                                  'Tu cuenta administradora conserva su rol y estado para que puedas seguir administrando.',
                                  style: TextStyle(color: AppColors.muted))),
                      ],
                      if (_error != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(_error!,
                                style:
                                    const TextStyle(color: AppColors.error))),
                    ])),
      actions: [
        if (_error != null)
          TextButton.icon(
              onPressed: _guardando || _cargando ? null : _leer,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Actualizar datos')),
        TextButton(
            onPressed: _guardando ? null : () => Navigator.pop(context),
            child: const Text('Cerrar')),
        FilledButton(
            onPressed:
                _cargando || _guardando || _conflicto || propio || sinCambios
                    ? null
                    : _guardar,
            child: Text(_guardando ? 'Guardando...' : 'Guardar permisos')),
      ],
    );
  }
}
