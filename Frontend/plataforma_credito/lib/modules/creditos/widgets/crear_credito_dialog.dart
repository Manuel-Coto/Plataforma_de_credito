import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../models/financiamiento.dart';
import '../../../services/api_client.dart';
import '../../../services/credito_service.dart';
import '../../../services/inversion_service.dart';

class CrearCreditoDialog extends StatefulWidget {
  const CrearCreditoDialog(
      {super.key, required this.api, required this.onCreado});
  final ApiClient api;
  final ValueChanged<ResultadoCredito> onCreado;
  @override
  State<CrearCreditoDialog> createState() => _CrearCreditoDialogState();
}

class _CrearCreditoDialogState extends State<CrearCreditoDialog> {
  final _form = GlobalKey<FormState>();
  final _ofertas = <Oferta>[];
  String? _seleccionada, _cursor, _error;
  bool _cargando = true, _ocupado = false, _hayMas = false;
  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar({bool mas = false}) async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final pagina = await InversionService(widget.api).ofertas(
          estado: 'objetivo_alcanzado', bookmark: mas ? _cursor : null);
      if (!mounted) return;
      setState(() {
        final anterior = mas ? _cursor : null;
        if (!mas) _ofertas.clear();
        final ids = _ofertas.map((item) => item.id).toSet();
        _ofertas.addAll(pagina.items.where((item) => ids.add(item.id)));
        _hayMas = pagina.items.isNotEmpty &&
            pagina.bookmark.isNotEmpty &&
            pagina.bookmark != anterior;
        _cursor = pagina.bookmark;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is ApiException
            ? error.message
            : 'No se pudieron cargar las ofertas.');
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _crear() async {
    if (_ocupado || !_form.currentState!.validate()) return;
    final oferta = _ofertas.firstWhere((item) => item.id == _seleccionada);
    final confirmar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Confirmar creación del crédito'),
                content: Text(
                    'Se creará un crédito para la factura ${oferta.facturaId}, con capital de ${money(oferta.objetivoCentavos, oferta.moneda)}. El servidor comprobará los aportes confirmados y calculará el interés.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Volver')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Crear crédito'))
                ]));
    if (!mounted || confirmar != true) return;
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final resultado = await CreditoService(widget.api).crear(oferta.id);
      if (!mounted) return;
      widget.onCreado(resultado);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(resultado.sincronizacionPendiente
              ? 'Crédito guardado. Hay actualizaciones relacionadas pendientes de sincronización.'
              : 'Crédito creado correctamente.')));
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is ApiException
            ? error.message
            : 'No se pudo confirmar la creación del crédito. Puedes reintentar la misma oferta.');
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_ocupado,
      child: AlertDialog(
        title: const Text('Crear crédito desde una oferta'),
        content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
                child: Form(
                    key: _form,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                              'Elige una oferta con objetivo alcanzado. Todos sus aportes deben estar confirmados antes de continuar.'),
                          const SizedBox(height: 18),
                          if (_cargando) const LinearProgressIndicator(),
                          if (_ofertas.isNotEmpty)
                            DropdownButtonFormField<String>(
                                initialValue: _seleccionada,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'Oferta financiada'),
                                items: [
                                  for (final oferta in _ofertas)
                                    DropdownMenuItem(
                                        value: oferta.id,
                                        child: Text(
                                            '${oferta.facturaId} · ${money(oferta.objetivoCentavos, oferta.moneda)}',
                                            overflow: TextOverflow.ellipsis))
                                ],
                                onChanged: _ocupado
                                    ? null
                                    : (value) =>
                                        setState(() => _seleccionada = value),
                                validator: (value) => value == null
                                    ? 'Selecciona una oferta'
                                    : null)
                          else if (!_cargando)
                            const Text(
                                'Todavía no hay ofertas con el objetivo alcanzado.'),
                          if (_hayMas)
                            TextButton(
                                onPressed: _cargando || _ocupado
                                    ? null
                                    : () => _cargar(mas: true),
                                child: const Text('Cargar más ofertas')),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Text(_error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                            if (_ofertas.isEmpty)
                              TextButton(
                                  onPressed: _cargando ? null : _cargar,
                                  child: const Text('Reintentar carga'))
                          ],
                        ])))),
        actions: [
          TextButton(
              onPressed: _ocupado ? null : () => Navigator.pop(context),
              child: const Text('Cerrar')),
          FilledButton(
              onPressed:
                  _ocupado || _cargando || _ofertas.isEmpty ? null : _crear,
              child: Text(_ocupado ? 'Creando...' : 'Revisar crédito'))
        ],
      ));
}
