import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../services/api_client.dart';
import '../../usuarios/providers/sesion_provider.dart';
import '../../../widgets/page_header.dart';
import 'empresa_form_screen.dart';
import '../../../services/empresa_service.dart';

class EmpresaRevisionScreen extends StatefulWidget {
  const EmpresaRevisionScreen({super.key});
  @override
  State<EmpresaRevisionScreen> createState() => _EmpresaRevisionScreenState();
}

class _EmpresaRevisionScreenState extends State<EmpresaRevisionScreen> {
  final List<Map<String, dynamic>> _empresas = [];
  final Set<String> _cursores = {};
  String? _bookmark;
  String? _error;
  bool _cargando = false;
  bool _fin = false;
  int _peticion = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _cargar();
    });
  }

  Future<void> _cargar({bool mas = false}) async {
    if (!mounted || (mas && (_cargando || _fin))) return;
    final sesion = context.read<SesionProvider>();
    if (!const ['pyme', 'administrador'].contains(sesion.usuario?['rol'])) {
      return;
    }
    final peticion = ++_peticion;
    final version = sesion.version;
    var cursor = mas ? _bookmark : null;
    setState(() {
      _cargando = true;
      _error = null;
      if (!mas) {
        _empresas.clear();
        _cursores.clear();
        _bookmark = null;
        _fin = false;
      }
    });
    try {
      final cursores = <String>{..._cursores};
      while (true) {
        final response = await sesion.api.get('/api/empresas', query: {
          'limit': '25',
          if (cursor != null) 'bookmark': cursor,
        });
        if (!mounted || peticion != _peticion || sesion.version != version) {
          return;
        }
        final data = response as Map<String, dynamic>;
        final lista = (data['empresas'] as List).cast<Map<String, dynamic>>();
        final siguiente = data['bookmark'] as String;
        for (final empresa in lista) {
          if (empresa['id'] is! String ||
              (empresa['id'] as String).isEmpty ||
              empresa['nombre'] is! String) {
            throw const FormatException('Empresa incompatible');
          }
        }
        final avanza = siguiente.isNotEmpty && cursores.add(siguiente);
        if (lista.isEmpty && avanza) {
          cursor = siguiente;
          continue;
        }
        setState(() {
          for (final empresa in lista) {
            final index =
                _empresas.indexWhere((item) => item['id'] == empresa['id']);
            if (index < 0) {
              _empresas.add(empresa);
            } else {
              _empresas[index] = empresa;
            }
          }
          _fin = !avanza;
          _cursores
            ..clear()
            ..addAll(cursores);
          _bookmark = siguiente;
        });
        break;
      }
    } on ApiException catch (e) {
      if (mounted && peticion == _peticion && sesion.version == version) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted && peticion == _peticion && sesion.version == version) {
        setState(() => _error = 'No se pudo leer el listado de empresas.');
      }
    } finally {
      if (mounted && peticion == _peticion && sesion.version == version) {
        setState(() => _cargando = false);
      }
    }
  }

  @override
  void dispose() {
    _peticion++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rol = context.watch<SesionProvider>().usuario?['rol'];
    final admin = rol == 'administrador';
    if (rol != 'pyme' && !admin) {
      return const Center(
          child: Text('Esta revisión requiere una cuenta administradora.'));
    }
    return ListView(padding: const EdgeInsets.all(24), children: [
      PageHeader(
          title: admin ? 'Revisión de empresas' : 'Mis empresas',
          subtitle: admin
              ? 'Consulta los datos y decide qué empresas pueden continuar.'
              : 'Consulta y actualiza la información de tus empresas.',
          action: OutlinedButton.icon(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar'))),
      const SizedBox(height: 24),
      if (rol == 'pyme')
        Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: FilledButton.icon(
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Registrar empresa'),
              onPressed: _cargando
                  ? null
                  : () async {
                      final api = context.read<SesionProvider>().api;
                      await Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (routeContext) => Scaffold(
                                appBar:
                                    AppBar(title: const Text('Nueva empresa')),
                                body: EmpresaFormScreen(
                                    onGuardar: EmpresaService(api).crear,
                                    onGuardado: () =>
                                        Navigator.pop(routeContext)),
                              )));
                      if (mounted) _cargar();
                    },
            )),
      if (_error != null) ...[
        Text(_error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
        TextButton(
            onPressed:
                _cargando ? null : () => _cargar(mas: _empresas.isNotEmpty),
            child: const Text('Reintentar')),
      ],
      if (!_cargando && _error == null && _empresas.isEmpty)
        const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No hay empresas registradas para revisar.')),
      for (final empresa in _empresas)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
              child: ListTile(
            contentPadding: const EdgeInsets.all(18),
            leading: const Icon(Icons.business_outlined),
            title: Text(empresa['nombre'] as String),
            subtitle:
                Text('NIT: ${empresa['nit']}\nEstado: ${empresa['estado']}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) =>
                      EmpresaDecisionScreen(id: empresa['id'] as String)));
              if (mounted) _cargar();
            },
          )),
        ),
      if (_cargando)
        const Center(
            child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator())),
      if (!_fin && !_cargando && _empresas.isNotEmpty)
        OutlinedButton(
            onPressed: () => _cargar(mas: true),
            child: const Text('Cargar más empresas')),
    ]);
  }
}

class EmpresaDecisionScreen extends StatefulWidget {
  const EmpresaDecisionScreen({super.key, required this.id});
  final String id;
  @override
  State<EmpresaDecisionScreen> createState() => _EmpresaDecisionScreenState();
}

class _EmpresaDecisionScreenState extends State<EmpresaDecisionScreen> {
  Map<String, dynamic>? _empresa;
  String? _etag;
  String? _error;
  bool _ocupado = false;
  String get _ruta => '/api/empresas/${Uri.encodeComponent(widget.id)}';

  Future<void> _editar() async {
    if (_ocupado || _empresa == null || _etag == null) return;
    final api = context.read<SesionProvider>().api;
    final revision = _etag!;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (routeContext) => Scaffold(
              appBar: AppBar(title: const Text('Editar empresa')),
              body: EmpresaFormScreen(
                  initialData: Map.of(_empresa!),
                  onGuardar: (datos) async {
                    try {
                      await api.put(_ruta, datos, ifMatch: revision);
                    } on ApiException catch (error) {
                      if (error.status == 409 || error.status == 412) {
                        throw ApiException(
                            'La empresa cambió. Vuelve al detalle y actualiza los datos antes de editar nuevamente.',
                            error.status);
                      }
                      rethrow;
                    }
                  },
                  onGuardado: () => Navigator.pop(routeContext)),
            )));
    if (mounted) await _consultar();
  }

  Future<void> _desactivar() async {
    if (_ocupado || _empresa == null || _etag == null) return;
    final confirmacion = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('¿Desactivar empresa?'),
              content: Text(
                  '${_empresa!['nombre']} quedará inactiva. No existe una opción de reactivación en la plataforma.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Desactivar'))
              ],
            ));
    if (confirmacion != true || !mounted || _ocupado) return;
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      await context.read<SesionProvider>().api.patch('$_ruta/desactivar', {});
      if (mounted) await _consultar();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _etag = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'No se pudo confirmar la desactivación. Actualiza los datos.';
          _etag = null;
        });
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _consultar();
    });
  }

  Future<void> _consultar({String? aviso}) async {
    setState(() {
      _ocupado = true;
      _etag = null;
      _error = aviso;
    });
    try {
      final response =
          await context.read<SesionProvider>().api.getConCabeceras(_ruta);
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final etag = response.headers['etag'];
      if (data['id'] != widget.id ||
          etag == null ||
          !RegExp(r'^"[A-Za-z0-9-]+"$').hasMatch(etag)) {
        throw const FormatException();
      }
      if (mounted) {
        setState(() {
          _empresa = data;
          _etag = etag;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'No se pudo cargar una versión válida de la empresa. Actualiza para continuar.');
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _decidir(bool aprobar) async {
    if (_ocupado || _etag == null) return;
    final confirmar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(aprobar ? '¿Aprobar empresa?' : '¿Rechazar empresa?'),
              content: Text(
                  '${_empresa!['nombre']} quedará ${aprobar ? 'activa' : 'rechazada'}. Esta decisión se guardará en la plataforma.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Confirmar'))
              ],
            ));
    if (confirmar != true || !mounted || _ocupado) return;
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      await context
          .read<SesionProvider>()
          .api
          .revisarEmpresa('$_ruta/${aprobar ? 'aprobar' : 'rechazar'}', _etag!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(aprobar
              ? 'Empresa aprobada correctamente.'
              : 'Empresa rechazada correctamente.')));
      await _consultar();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 409 || e.status == 412) {
        await _consultar(
            aviso:
                'La empresa cambió o su estado no permite esta decisión. Revisa los datos actualizados antes de decidir nuevamente.');
      } else {
        setState(() {
          _error = e.message;
          _etag = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _etag = null;
          _error =
              'No se pudo confirmar el resultado. Actualiza la empresa antes de continuar.';
        });
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin =
        context.watch<SesionProvider>().usuario?['rol'] == 'administrador';
    final gestion =
        admin || context.read<SesionProvider>().usuario?['rol'] == 'pyme';
    final empresa = _empresa;
    final responsable = empresa?['usuario_responsable_id'];
    final revisable = admin &&
        empresa?['estado'] == 'pendiente' &&
        responsable is String &&
        responsable.trim().isNotEmpty &&
        _etag != null;
    return Scaffold(
        appBar: AppBar(title: const Text('Detalle de empresa')),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          if (_ocupado) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          if (empresa != null)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(empresa['nombre'] as String,
                              style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 20),
                          for (final field in {
                            'nit': 'NIT',
                            'estado': 'Estado',
                            'correo': 'Correo',
                            'telefono': 'Teléfono',
                            'direccion': 'Dirección',
                            'usuario_responsable_id': 'Responsable',
                            'fecha_creacion': 'Fecha de registro'
                          }.entries)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: SelectableText(
                                    '${field.value}: ${empresa[field.key] ?? 'No disponible'}')),
                        ]))),
          const SizedBox(height: 20),
          if (revisable)
            Wrap(spacing: 12, runSpacing: 12, children: [
              FilledButton.icon(
                  onPressed: _ocupado ? null : () => _decidir(true),
                  icon: const Icon(Icons.check),
                  label: const Text('Aprobar empresa')),
              OutlinedButton.icon(
                  onPressed: _ocupado ? null : () => _decidir(false),
                  icon: const Icon(Icons.close),
                  label: const Text('Rechazar empresa')),
            ])
          else if (empresa != null)
            const Text(
                'Solo se pueden revisar empresas pendientes que tengan un responsable asignado.'),
          const SizedBox(height: 12),
          if (gestion && empresa != null)
            Wrap(spacing: 12, runSpacing: 12, children: [
              OutlinedButton.icon(
                  onPressed: _ocupado || _etag == null ? null : _editar,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar empresa')),
              if (empresa['estado'] != 'inactiva')
                OutlinedButton.icon(
                    onPressed: _ocupado || _etag == null ? null : _desactivar,
                    icon: const Icon(Icons.block),
                    label: const Text('Desactivar empresa')),
            ]),
          TextButton.icon(
              onPressed: _ocupado ? null : _consultar,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar datos')),
        ]));
  }
}
