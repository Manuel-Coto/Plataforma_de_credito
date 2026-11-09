import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/format.dart';
import '../../../models/resumen.dart';
import '../../../services/api_client.dart';
import '../../../widgets/page_header.dart';
import '../../usuarios/providers/sesion_provider.dart';

class ReportesAuditoriaScreen extends StatefulWidget {
  const ReportesAuditoriaScreen({super.key});
  @override
  State<ReportesAuditoriaScreen> createState() =>
      _ReportesAuditoriaScreenState();
}

class _ReportesAuditoriaScreenState extends State<ReportesAuditoriaScreen> {
  final _actor = TextEditingController();
  final _recurso = TextEditingController();
  final List<Map<String, dynamic>> _eventos = [];
  final Set<String> _cursores = {};
  String _modo = 'reportes';
  String _modulo = 'creditos';
  String _actorAplicado = '';
  String _recursoAplicado = '';
  String? _bookmark;
  String? _error;
  ReporteResumen? _reporte;
  bool _cargando = false;
  bool _fin = false;
  int _peticion = 0;
  static const _modulos = {
    'usuarios': 'Usuarios',
    'empresas': 'Empresas',
    'facturas': 'Facturas',
    'ofertas': 'Ofertas',
    'inversiones': 'Inversiones',
    'creditos': 'Créditos',
    'pagos': 'Pagos',
    'auditoria': 'Auditoría'
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _cargar();
    });
  }

  @override
  void dispose() {
    _peticion++;
    _actor.dispose();
    _recurso.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool mas = false}) async {
    if (!mounted || (mas && (_cargando || _fin))) return;
    if (context.read<SesionProvider>().usuario?['rol'] != 'administrador') {
      return;
    }
    final solicitud = ++_peticion;
    final auditoria = _modo == 'auditoria';
    var cursorConsulta = mas ? _bookmark : null;
    if (auditoria && !mas) {
      _actorAplicado = _actor.text.trim();
      _recursoAplicado = _recurso.text.trim();
    }
    setState(() {
      _cargando = true;
      _error = null;
      if (!mas) {
        _reporte = null;
        _eventos.clear();
        _cursores.clear();
        _bookmark = null;
        _fin = false;
      }
    });
    try {
      final api = context.read<SesionProvider>().api;
      final cursores = <String>{..._cursores};
      while (true) {
        final data = await api.get(
            auditoria
                ? '/api/administracion/auditoria'
                : '/api/administracion/reportes',
            query: auditoria
                ? {
                    'limit': '25',
                    if (_actorAplicado.isNotEmpty) 'actor_id': _actorAplicado,
                    if (_recursoAplicado.isNotEmpty)
                      'recurso_id': _recursoAplicado,
                    if (cursorConsulta != null) 'bookmark': cursorConsulta,
                  }
                : {'modulo': _modulo});
        if (!mounted || solicitud != _peticion) return;
        if (data is! Map<String, dynamic>) throw const FormatException();
        if (!auditoria) {
          final reporte = ReporteResumen.fromJson(data);
          if (reporte.modulo != _modulo) throw const FormatException();
          setState(() => _reporte = reporte);
        } else {
          final eventos =
              (data['eventos'] as List).cast<Map<String, dynamic>>();
          final cursor = data['bookmark'] as String;
          for (final evento in eventos) {
            for (final key in [
              'id',
              'actor_id',
              'accion',
              'recurso_tipo',
              'recurso_id',
              'fecha'
            ]) {
              if (evento[key] is! String) throw const FormatException();
            }
            DateTime.parse(evento['fecha'] as String);
            if (evento['detalles'] is! Map) throw const FormatException();
          }
          final avanza = cursor.isNotEmpty && cursores.add(cursor);
          if (eventos.isEmpty && avanza) {
            cursorConsulta = cursor;
            continue;
          }
          setState(() {
            for (final evento in eventos) {
              if (!_eventos.any((item) => item['id'] == evento['id'])) {
                _eventos.add(evento);
              }
            }
            _fin = !avanza;
            _cursores
              ..clear()
              ..addAll(cursores);
            _bookmark = cursor;
          });
        }
        break;
      }
    } on ApiException catch (e) {
      if (mounted && solicitud == _peticion) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && solicitud == _peticion) {
        setState(() =>
            _error = 'No se pudo leer la información. Intenta nuevamente.');
      }
    } finally {
      if (mounted && solicitud == _peticion) setState(() => _cargando = false);
    }
  }

  String _legible(String value) {
    final text = estadoLegible(value);
    return text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
  }

  String _detalle(Map detalles, MapEntry entry) {
    final label = _montos[entry.key] ?? _legible(entry.key.toString());
    if (entry.key.toString().endsWith('_centavos') && entry.value is int) {
      final moneda = detalles['moneda'];
      return '$label: ${moneda is String && moneda.isNotEmpty ? money(entry.value as int, moneda) : '${entry.value} centavos'}';
    }
    return '$label: ${entry.value}';
  }

  static const _montos = {
    'monto_centavos': 'Monto',
    'capital_centavos': 'Capital',
    'interes_centavos': 'Interés',
    'total_centavos': 'Total',
    'pagado_centavos': 'Pagado',
    'saldo_centavos': 'Saldo',
    'financiado_centavos': 'Financiado',
    'objetivo_centavos': 'Objetivo',
    'recaudado_centavos': 'Recaudado',
    'invertido_centavos': 'Invertido'
  };

  @override
  Widget build(BuildContext context) {
    if (context.watch<SesionProvider>().usuario?['rol'] != 'administrador') {
      return const Center(
          child: Text('Esta sección requiere una cuenta administradora.'));
    }
    final reporte = _reporte;
    return ListView(padding: const EdgeInsets.all(24), children: [
      PageHeader(
          title: 'Reportes y auditoría',
          subtitle:
              'Consulta cifras por módulo y el historial de movimientos registrados.',
          action: OutlinedButton.icon(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar'))),
      const SizedBox(height: 24),
      Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'reportes',
                    label: Text('Reportes'),
                    icon: Icon(Icons.bar_chart)),
                ButtonSegment(
                    value: 'auditoria',
                    label: Text('Auditoría'),
                    icon: Icon(Icons.history)),
              ],
              selected: {
                _modo
              },
              onSelectionChanged: _cargando
                  ? null
                  : (value) {
                      setState(() => _modo = value.single);
                      _cargar();
                    })),
      const SizedBox(height: 24),
      if (_modo == 'reportes')
        DropdownButtonFormField<String>(
          initialValue: _modulo,
          decoration: const InputDecoration(labelText: 'Módulo'),
          items: [
            for (final entry in _modulos.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value))
          ],
          onChanged: _cargando
              ? null
              : (value) {
                  if (value != null) {
                    setState(() => _modulo = value);
                    _cargar();
                  }
                },
        )
      else ...[
        const Text('Filtros opcionales por identificador exacto.'),
        const SizedBox(height: 12),
        TextField(
            controller: _actor,
            maxLength: 512,
            enabled: !_cargando,
            decoration: const InputDecoration(
                labelText: 'Usuario que realizó la acción (ID)')),
        const SizedBox(height: 12),
        TextField(
            controller: _recurso,
            maxLength: 512,
            enabled: !_cargando,
            decoration: const InputDecoration(labelText: 'Recurso (ID)')),
        Wrap(spacing: 12, runSpacing: 12, children: [
          FilledButton.icon(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.search),
              label: const Text('Aplicar filtros')),
          TextButton(
              onPressed: _cargando
                  ? null
                  : () {
                      _actor.clear();
                      _recurso.clear();
                      _cargar();
                    },
              child: const Text('Limpiar filtros')),
        ]),
      ],
      if (_error != null)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              TextButton(
                  onPressed: _cargando
                      ? null
                      : () => _cargar(
                          mas: _modo == 'auditoria' && _eventos.isNotEmpty),
                  child: const Text('Reintentar')),
            ])),
      const SizedBox(height: 24),
      if (reporte != null && _modo == 'reportes') ...[
        Card(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_modulos[reporte.modulo]!,
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      Text('Total de registros: ${reporte.total}'),
                      if (reporte.porEstado.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text('Por estado'),
                        for (final entry in reporte.porEstado.entries)
                          ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(_legible(entry.key)),
                              trailing: Text('${entry.value}'))
                      ],
                      if (reporte.porRol.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text('Por rol'),
                        for (final entry in reporte.porRol.entries)
                          ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(_legible(entry.key)),
                              trailing: Text('${entry.value}'))
                      ],
                    ]))),
        for (final moneda in reporte.montosPorMoneda.entries)
          Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Card(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Importes en ${moneda.key}',
                                style: Theme.of(context).textTheme.titleMedium),
                            for (final importe in moneda.value.entries)
                              Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Wrap(
                                      spacing: 16,
                                      runSpacing: 4,
                                      children: [
                                        Text(_montos[importe.key] ??
                                            _legible(importe.key)),
                                        Text(money(importe.value, moneda.key)),
                                      ])),
                          ])))),
      ],
      if (_modo == 'auditoria') ...[
        const Text(
            'El orden de consulta no garantiza una secuencia cronológica.'),
        const SizedBox(height: 12),
        if (!_cargando && _error == null && _eventos.isEmpty)
          const Text('No hay eventos con estos filtros.'),
        for (final evento in _eventos)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                  child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_legible(evento['accion'] as String),
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 10),
                            SelectableText(
                                'Usuario: ${evento['actor_id']}\nRecurso: ${evento['recurso_tipo']} · ${evento['recurso_id']}\nFecha local: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(evento['fecha'] as String).toLocal())}'),
                            for (final entry
                                in (evento['detalles'] as Map).entries)
                              Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: SelectableText(_detalle(
                                      evento['detalles'] as Map, entry))),
                          ])))),
        if (!_cargando && !_fin && _eventos.isNotEmpty)
          OutlinedButton(
              onPressed: () => _cargar(mas: true),
              child: const Text('Cargar más eventos')),
      ],
      if (_cargando)
        const Center(
            child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator())),
    ]);
  }
}
