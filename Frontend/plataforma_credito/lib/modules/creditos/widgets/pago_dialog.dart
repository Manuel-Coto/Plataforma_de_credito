import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../models/financiamiento.dart';
import '../../../services/api_client.dart';

class PagoDialog extends StatefulWidget {
  const PagoDialog(
      {super.key,
      required this.saldoCentavos,
      required this.moneda,
      required this.onGuardar,
      required this.montoPendiente});
  final int saldoCentavos;
  final String moneda;
  final Future<ResultadoCredito> Function(int) onGuardar;
  final int? Function() montoPendiente;
  @override
  State<PagoDialog> createState() => _PagoDialogState();
}

class _PagoDialogState extends State<PagoDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _monto;
  bool _ocupado = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final previo = widget.montoPendiente();
    _monto = TextEditingController(
        text: previo == null ? '' : (previo / 100).toStringAsFixed(2));
  }

  @override
  void dispose() {
    _monto.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_ocupado || !_form.currentState!.validate()) return;
    final monto = textoACentavos(_monto.text)!;
    if (widget.montoPendiente() == null) {
      final confirmar = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Confirmar pago simulado'),
                content: Text(
                    'Registrarás ${money(monto, widget.moneda)} en este crédito. No se realizará ningún cobro bancario.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Volver')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Confirmar pago'))
                ],
              ));
      if (!mounted || confirmar != true) return;
    }
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final resultado = await widget.onGuardar(monto);
      if (mounted) Navigator.pop(context, resultado);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is ApiException
            ? error.message
            : 'No se pudo confirmar el pago. Reintenta para comprobar el mismo registro.');
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendiente = widget.montoPendiente() != null;
    return PopScope(
        canPop: !_ocupado,
        child: AlertDialog(
          title: const Text('Registrar pago simulado'),
          content: SizedBox(
              width: 430,
              child: SingleChildScrollView(
                  child: Form(
                      key: _form,
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'Saldo pendiente: ${money(widget.saldoCentavos, widget.moneda)}'),
                            const SizedBox(height: 18),
                            TextFormField(
                                controller: _monto,
                                enabled: !_ocupado && !pendiente,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: InputDecoration(
                                    labelText:
                                        'Monto del pago (${widget.moneda})',
                                    helperText: 'Hasta dos decimales'),
                                validator: (value) {
                                  final cents = textoACentavos(value ?? '');
                                  if (cents == null) {
                                    return 'Escribe un monto válido mayor que cero';
                                  }
                                  if (!pendiente &&
                                      cents > widget.saldoCentavos) {
                                    return 'El monto supera el saldo pendiente';
                                  }
                                  return null;
                                }),
                            const SizedBox(height: 16),
                            Text(pendiente
                                ? 'Hay un pago sin respuesta confirmada. Reintenta con el mismo monto; se conservará su referencia.'
                                : 'Este pago es una simulación. La referencia del registro se conservará si necesitas reintentarlo.'),
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              Text(_error!,
                                  style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error))
                            ],
                          ])))),
          actions: [
            TextButton(
                onPressed: _ocupado ? null : () => Navigator.pop(context),
                child: const Text('Cerrar')),
            FilledButton(
                onPressed: _ocupado ? null : _guardar,
                child: Text(_ocupado
                    ? 'Registrando...'
                    : pendiente
                        ? 'Reintentar pago'
                        : 'Revisar pago'))
          ],
        ));
  }
}
