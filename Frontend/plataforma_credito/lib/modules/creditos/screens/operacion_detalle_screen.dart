import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme/credito_theme.dart';
import '../../../models/operacion.dart';
import '../../../models/financiamiento.dart';
import '../../../services/api_client.dart';
import '../widgets/pago_dialog.dart';

class OperacionDetalleScreen extends StatefulWidget {
  const OperacionDetalleScreen(
      {super.key,
      required this.operacion,
      this.onPagar,
      this.onSincronizar,
      this.onActualizar,
      this.montoPendiente,
      this.sincronizacionPendiente = false});
  final Operacion operacion;
  final Future<ResultadoCredito> Function(int)? onPagar;
  final Future<ResultadoCredito> Function()? onSincronizar;
  final Future<Operacion> Function()? onActualizar;
  final int? Function()? montoPendiente;
  final bool sincronizacionPendiente;
  @override
  State<OperacionDetalleScreen> createState() => _OperacionDetalleScreenState();
}

class _OperacionDetalleScreenState extends State<OperacionDetalleScreen> {
  late Operacion _operacion;
  late bool _pendiente;
  bool _ocupado = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _operacion = widget.operacion;
    _pendiente = widget.sincronizacionPendiente;
    if (widget.onActualizar != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _actualizar();
      });
    }
  }

  Future<void> _actualizar() async {
    if (_ocupado || widget.onActualizar == null) return;
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final actualizado = await widget.onActualizar!();
      if (mounted) setState(() => _operacion = actualizado);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is ApiException
            ? error.message
            : 'No se pudo actualizar el crédito.');
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _pagar() async {
    if (_ocupado || widget.onPagar == null) return;
    final resultado = await showDialog<ResultadoCredito>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PagoDialog(
            saldoCentavos: _operacion.saldoCentavos,
            moneda: _operacion.moneda,
            onGuardar: widget.onPagar!,
            montoPendiente: widget.montoPendiente ?? () => null));
    if (mounted && resultado != null) {
      _aplicar(resultado, 'Pago simulado registrado.');
    }
  }

  Future<void> _sincronizar() async {
    if (_ocupado || widget.onSincronizar == null) return;
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final resultado = await widget.onSincronizar!();
      if (mounted) _aplicar(resultado, 'Sincronización completada.');
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is ApiException
            ? error.message
            : 'No se pudo completar la sincronización.');
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _aplicar(ResultadoCredito resultado, String mensaje) {
    setState(() {
      _operacion = resultado.credito;
      _pendiente = resultado.sincronizacionPendiente;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_pendiente
            ? 'El registro está guardado; quedan actualizaciones relacionadas por sincronizar.'
            : mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    final o = _operacion;
    final texto = Theme.of(context).textTheme;
    final historial = o.pagos;
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del crédito'), actions: [
        if (widget.onActualizar != null)
          IconButton(
              tooltip: 'Actualizar crédito',
              onPressed: _ocupado ? null : _actualizar,
              icon: const Icon(Icons.refresh))
      ]),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (_ocupado) const LinearProgressIndicator(),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: AppColors.error)),
                const SizedBox(height: 16)
              ],
              if (_pendiente) ...[
                _aviso(Icons.sync_rounded,
                    'El crédito o pago ya está guardado. Hay actualizaciones relacionadas pendientes de sincronización.'),
                const SizedBox(height: 16)
              ],
              Text('Factura ${o.facturaId}', style: texto.titleLarge),
              const SizedBox(height: 10),
              Wrap(spacing: 12, runSpacing: 10, children: [
                Text(estadoLegible(o.estadoVisible),
                    style: texto.bodyMedium?.copyWith(
                        color: o.vencido ? AppColors.error : AppColors.primary,
                        fontWeight: FontWeight.w700)),
                Text('Vence ${fecha(o.vencimiento)}',
                    style: texto.bodyMedium?.copyWith(color: AppColors.muted)),
              ]),
              if (o.vencido) ...[
                const SizedBox(height: 10),
                Text(
                    '${o.diasMora} ${o.diasMora == 1 ? 'día' : 'días'} de mora',
                    style: texto.bodyMedium?.copyWith(color: AppColors.error)),
              ],
              const SizedBox(height: 24),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Saldo pendiente',
                          style: TextStyle(color: AppColors.muted)),
                      const SizedBox(height: 7),
                      Text(money(o.saldoCentavos, o.moneda),
                          style: texto.headlineMedium),
                      const SizedBox(height: 23),
                      Wrap(spacing: 30, runSpacing: 20, children: [
                        _importe(context, 'Capital', o.capitalCentavos),
                        _importe(context, 'Interés', o.interesCentavos),
                        _importe(context, 'Total del crédito', o.totalCentavos),
                        _importe(context, 'Pagado', o.pagadoCentavos),
                      ]),
                      const SizedBox(height: 24),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: o.progreso,
                          minHeight: 8,
                          backgroundColor: AppColors.softPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text('${(o.progreso * 100).round()}% del crédito pagado',
                          style: texto.bodySmall
                              ?.copyWith(color: AppColors.muted)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Wrap(spacing: 12, runSpacing: 12, children: [
                if (widget.onPagar != null &&
                    (o.saldoCentavos > 0 ||
                        widget.montoPendiente?.call() != null))
                  FilledButton.icon(
                      onPressed: _ocupado ? null : _pagar,
                      icon: const Icon(Icons.add_card_outlined),
                      label: Text(widget.montoPendiente?.call() != null
                          ? 'Resolver pago pendiente'
                          : 'Registrar pago simulado')),
                if (widget.onSincronizar != null)
                  OutlinedButton.icon(
                      onPressed: _ocupado ? null : _sincronizar,
                      icon: const Icon(Icons.sync_rounded),
                      label: const Text('Sincronizar')),
              ]),
              const SizedBox(height: 24),
              Text('Historial de pagos', style: texto.titleLarge),
              const SizedBox(height: 8),
              const Text('Los pagos de esta plataforma son simulados.',
                  style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 18),
              if (historial == null)
                _aviso(Icons.lock_outline_rounded,
                    'El historial de pagos no se comparte con tu perfil. Los importes del crédito sí están disponibles.')
              else if (historial.isEmpty)
                _aviso(Icons.receipt_long_outlined,
                    'Todavía no se registran pagos.')
              else
                for (final pago in historial) _pago(context, pago),
            ],
          ),
        ),
      ),
    );
  }

  Widget _importe(BuildContext context, String label, int centavos) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 6),
          Text(money(centavos, _operacion.moneda),
              style: Theme.of(context).textTheme.titleMedium),
        ],
      );

  Widget _aviso(IconData icon, String message) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: AppColors.muted, size: 22),
            const SizedBox(width: 13),
            Expanded(
                child: Text(message,
                    style:
                        const TextStyle(color: AppColors.muted, height: 1.5))),
          ]),
        ),
      );

  Widget _pago(BuildContext context, Pago pago) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.check_circle_outline_rounded,
                color: AppColors.primary, size: 23),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(money(pago.montoCentavos, _operacion.moneda),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text('Referencia: ${pago.referencia}',
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('Registrado el ${fecha(pago.fecha.toLocal())}',
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 12)),
                ],
              ),
            ),
          ]),
        ),
      );
}
