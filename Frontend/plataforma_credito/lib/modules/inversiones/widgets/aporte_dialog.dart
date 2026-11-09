import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../models/financiamiento.dart';
import '../providers/inversiones_provider.dart';

class AporteDialog extends StatefulWidget {
  const AporteDialog({super.key, required this.oferta, required this.provider});
  final Oferta oferta;
  final InversionesProvider provider;
  @override
  State<AporteDialog> createState() => _AporteDialogState();
}

class _AporteDialogState extends State<AporteDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _monto;
  bool _ocupado = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final previo = widget.provider.intentoPendiente(widget.oferta.id);
    _monto = TextEditingController(
        text: previo == null
            ? ''
            : (previo.montoCentavos / 100).toStringAsFixed(2));
  }

  @override
  void dispose() {
    _monto.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_ocupado || !_form.currentState!.validate()) return;
    final monto = textoACentavos(_monto.text)!;
    if (widget.provider.intentoPendiente(widget.oferta.id) == null) {
      final confirmar = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Confirmar aporte simulado'),
                  content: Text(
                      'Registrarás un aporte de ${money(monto, widget.oferta.moneda)} para la factura ${widget.oferta.facturaId}. Luego deberás confirmar su pago simulado desde tu historial. No se moverá dinero real.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Volver')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Confirmar aporte'))
                  ]));
      if (!mounted || confirmar != true) return;
    }
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final inversion = await widget.provider.invertir(widget.oferta, monto);
      if (mounted) Navigator.pop(context, inversion);
    } catch (error) {
      if (mounted) setState(() => _error = mensajeFinanciero(error));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendiente =
        widget.provider.intentoPendiente(widget.oferta.id) != null;
    return PopScope(
        canPop: !_ocupado,
        child: AlertDialog(
          title: const Text('Aportar a una oferta'),
          content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                  child: Form(
                      key: _form,
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Factura ${widget.oferta.facturaId}'),
                            const SizedBox(height: 8),
                            Text(
                                'Disponible: ${money(widget.oferta.disponibleCentavos, widget.oferta.moneda)}'),
                            const SizedBox(height: 20),
                            TextFormField(
                                controller: _monto,
                                enabled: !_ocupado && !pendiente,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: InputDecoration(
                                    labelText:
                                        'Monto del aporte (${widget.oferta.moneda})',
                                    helperText: 'Hasta dos decimales'),
                                validator: (value) {
                                  final monto = textoACentavos(value ?? '');
                                  if (monto == null) {
                                    return 'Escribe un monto válido mayor que cero';
                                  }
                                  if (!pendiente &&
                                      monto >
                                          widget.oferta.disponibleCentavos) {
                                    return 'El aporte supera el saldo disponible';
                                  }
                                  return null;
                                }),
                            const SizedBox(height: 18),
                            Text(pendiente
                                ? 'Este aporte aún no tiene una respuesta confirmada. Reintenta con el mismo monto para recuperar su resultado sin duplicarlo.'
                                : 'Los aportes y sus pagos son simulados. La confirmación del pago se realiza desde el historial de inversiones.'),
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
                        ? 'Reintentar aporte'
                        : 'Revisar aporte'))
          ],
        ));
  }
}
