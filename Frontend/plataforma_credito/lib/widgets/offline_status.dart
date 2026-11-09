import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/theme/credito_theme.dart';
import '../services/api_client.dart';

class OfflineStatus extends StatelessWidget {
  const OfflineStatus({super.key, required this.api});
  final ApiClient api;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: api.offline,
        builder: (context, _) {
          final status = api.offline;
          if (!status.isOffline &&
              !status.usingSnapshot &&
              status.operations.isEmpty &&
              status.storageError == null) {
            return const SizedBox.shrink();
          }
          final message = status.storageError != null
              ? 'No se pudo guardar la información en este equipo.'
              : status.isOffline || status.usingSnapshot
                  ? 'Sin conexión · ${status.operations.length} cambios pendientes'
                  : '${status.operations.length} cambios por revisar o sincronizar';
          return Container(
            color: AppColors.softPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              Icon(status.isOffline ? Icons.cloud_off_outlined : Icons.sync,
                  size: 20, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(message, style: const TextStyle(fontSize: 12))),
              TextButton(
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => SincronizacionScreen(api: api))),
                  child: const Text('Sincronización')),
            ]),
          );
        },
      );
}

class SincronizacionScreen extends StatefulWidget {
  const SincronizacionScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<SincronizacionScreen> createState() => _SincronizacionScreenState();
}

class _SincronizacionScreenState extends State<SincronizacionScreen> {
  bool _ocupado = false;
  String? _mensaje;
  ApiClient get api => widget.api;

  Future<void> _ejecutar(Future<void> Function() action) async {
    if (_ocupado || api.offline.syncing) return;
    setState(() {
      _ocupado = true;
      _mensaje = null;
    });
    try {
      await action();
      if (mounted) {
        setState(() => _mensaje =
            'Revisión terminada. Consulta el estado de cada cambio y actualiza las listas para ver los datos del servidor.');
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _mensaje = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _mensaje =
            'No se pudo completar la sincronización. Intenta nuevamente.');
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _descartar(OutboxOperation operation) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('¿Eliminar cambio pendiente?'),
              content: const Text(
                  'Se eliminará esta copia local. Esta acción no deshace cambios que el servidor ya haya guardado.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Volver')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Eliminar copia local')),
              ],
            ));
    if (confirmed == true && mounted) {
      await _ejecutar(() => api.offline.descartar(operation.id));
    }
  }

  Future<void> _resolver(OutboxOperation operation) => _ejecutar(() async {
        final response = await api.consultarConflicto(operation.id);
        final current =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final etag = response.headers['etag'];
        if (etag == null || etag.isEmpty) {
          throw ApiException(
              'No se pudo consultar la revisión actual de la empresa.');
        }
        if (!mounted) return;
        final apply = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
                  title: const Text('Revisar cambios de la empresa'),
                  content: SizedBox(
                      width: 600,
                      child: SingleChildScrollView(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                              'La empresa cambió desde tu última consulta. Revisa ambas versiones antes de aplicar tus datos. Una empresa activa o rechazada volverá a revisión.'),
                          const SizedBox(height: 20),
                          _DatosCambio(
                              title: 'Versión actual del servidor',
                              values: current),
                          const SizedBox(height: 20),
                          _DatosCambio(
                              title: 'Tus cambios pendientes',
                              values: operation.body),
                        ],
                      ))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Volver')),
                    FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Aplicar mis cambios')),
                  ],
                ));
        if (apply == true && mounted) {
          await api.reintentarOperacion(operation.id, ifMatch: etag);
        }
      });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: api.offline,
        builder: (context, _) {
          final status = api.offline;
          final busy = _ocupado || status.syncing;
          return Scaffold(
            appBar: AppBar(title: const Text('Sincronización')),
            body: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView(padding: const EdgeInsets.all(24), children: [
                    Text(
                        status.isOffline
                            ? 'Estás trabajando sin conexión'
                            : 'Tus cambios, bajo control',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    const Text(
                        'Puedes consultar información que ya abriste y guardar empresas o facturas para enviarlas después. Los datos guardados pueden haber cambiado. Los pagos, inversiones, verificaciones y acciones de administración requieren conexión.'),
                    if (status.snapshotAt != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                              'Consulta guardada: ${_fecha(status.snapshotAt!)}')),
                    const SizedBox(height: 12),
                    const Text(
                        'El inicio de sesión requiere conexión. Cerrar sesión, vencer la sesión o cambiar de rol elimina las consultas y cambios locales. Al cerrar la aplicación se conservan cifrados para esta cuenta.'),
                    if (status.storageError != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                              'No se pudo guardar en este equipo: ${status.storageError}',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                    const SizedBox(height: 20),
                    Wrap(spacing: 12, runSpacing: 12, children: [
                      FilledButton.icon(
                          onPressed: busy
                              ? null
                              : () => _ejecutar(api.sincronizarPendientes),
                          icon: busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.sync),
                          label: Text(busy
                              ? 'Sincronizando...'
                              : 'Sincronizar pendientes')),
                      Text(
                          '${status.pendingCount} pendientes · ${status.conflictCount} conflictos · ${status.errorCount} errores'),
                    ]),
                    if (_mensaje != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(_mensaje!)),
                    const SizedBox(height: 20),
                    if (status.operations.isEmpty)
                      const Card(
                          child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('No tienes cambios pendientes.'))),
                    for (final operation in status.operations)
                      Card(
                          child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_nombre(operation),
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 6),
                              Text(
                                  '${_estado(operation.status)} · ${_fecha(operation.createdAt)} · ${operation.attempts} intentos'),
                              const SizedBox(height: 12),
                              _DatosCambio(values: operation.body),
                              if (operation.lastError != null)
                                Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Text(operation.lastError!)),
                              const SizedBox(height: 12),
                              Wrap(spacing: 12, runSpacing: 8, children: [
                                if (operation.status == OutboxStatus.conflict &&
                                    operation.method == 'PUT')
                                  FilledButton(
                                      onPressed: busy
                                          ? null
                                          : () => _resolver(operation),
                                      child: const Text('Revisar conflicto')),
                                if (operation.status != OutboxStatus.conflict &&
                                    operation.status != OutboxStatus.pending)
                                  OutlinedButton(
                                      onPressed: busy
                                          ? null
                                          : () => _ejecutar(() =>
                                              api.reintentarOperacion(
                                                  operation.id)),
                                      child:
                                          const Text('Reintentar este cambio')),
                                TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => _descartar(operation),
                                    child: const Text('Eliminar copia local')),
                              ]),
                              if (operation.status == OutboxStatus.conflict &&
                                  operation.method == 'POST')
                                const Text(
                                    'El registro entra en conflicto con el servidor. Consulta la empresa o factura existente antes de eliminar esta copia y corregir los datos.'),
                            ]),
                      )),
                  ]),
                )),
          );
        },
      );
}

String _fecha(DateTime value) => value.toLocal().toString().substring(0, 16);
String _nombre(OutboxOperation operation) => operation.route == '/api/facturas'
    ? 'Registrar factura'
    : operation.method == 'PUT'
        ? 'Editar empresa'
        : 'Registrar empresa';
String _estado(OutboxStatus status) => switch (status) {
      OutboxStatus.pending => 'Pendiente de envío',
      OutboxStatus.conflict => 'Requiere revisar un conflicto',
      OutboxStatus.error => 'Requiere atención',
    };

class _DatosCambio extends StatelessWidget {
  const _DatosCambio({this.title, required this.values});
  final String? title;
  final Map<String, dynamic> values;
  static const _labels = {
    'nombre': 'Nombre',
    'nit': 'NIT',
    'correo': 'Correo',
    'telefono': 'Teléfono',
    'direccion': 'Dirección',
    'numero': 'Número de factura',
    'empresa_id': 'Empresa',
    'codigo_generacion': 'Código DTE',
    'moneda': 'Moneda',
    'fecha_emision': 'Emisión',
    'fecha_vencimiento': 'Vencimiento',
  };
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null)
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(title!,
                  style: const TextStyle(fontWeight: FontWeight.bold))),
        for (final entry in _labels.entries)
          if (values.containsKey(entry.key))
            Text('${entry.value}: ${values[entry.key]}'),
        if (values['monto_total_centavos'] is int)
          Text(
              'Monto: ${values['moneda'] ?? 'USD'} ${(values['monto_total_centavos'] as int) ~/ 100}.${((values['monto_total_centavos'] as int) % 100).toString().padLeft(2, '0')}'),
      ]);
}
