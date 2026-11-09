import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme/credito_theme.dart';
import '../../../models/estado_factura.dart';
import '../../../models/factura.dart';
import '../../../models/financiamiento.dart';
import '../../../services/api_client.dart';
import '../../../services/factura_service.dart';
import '../../../services/inversion_service.dart';
import '../../../widgets/page_header.dart';

class PublicarOfertaScreen extends StatefulWidget {
  const PublicarOfertaScreen({super.key, required this.api});
  final ApiClient api;
  @override
  State<PublicarOfertaScreen> createState() => _PublicarOfertaScreenState();
}

class _PublicarOfertaScreenState extends State<PublicarOfertaScreen> {
  final _form = GlobalKey<FormState>();
  final _monto = TextEditingController(),
      _tasa = TextEditingController(text: '8.00');
  final _facturas = <Factura>[];
  String? _facturaId, _cursor, _error;
  DateTime? _cierre;
  bool _cargando = true, _ocupado = false, _hayMas = false;
  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _monto.dispose();
    _tasa.dispose();
    super.dispose();
  }

  Factura? get _factura {
    for (final factura in _facturas) {
      if (factura.id == _facturaId) return factura;
    }
    return null;
  }

  Future<void> _cargar({bool mas = false}) async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final pagina = await FacturaService(widget.api).listar(
          estado: EstadoFactura.disponible,
          limit: 100,
          bookmark: mas ? _cursor : null);
      if (!mounted) return;
      setState(() {
        final previo = mas ? _cursor : null;
        if (!mas) _facturas.clear();
        final hoy = DateTime.now();
        final ids = _facturas.map((f) => f.id).toSet();
        _facturas.addAll(pagina.facturas.where((f) =>
            f.dte.verificado &&
            f.fechaVencimiento
                .isAfter(DateTime(hoy.year, hoy.month, hoy.day)) &&
            ids.add(f.id)));
        _hayMas = pagina.facturas.isNotEmpty &&
            pagina.bookmark.isNotEmpty &&
            pagina.bookmark != previo;
        _cursor = pagina.bookmark;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is ApiException
            ? error.message
            : 'No se pudieron cargar las facturas.');
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _fecha() async {
    final ahora = DateTime.now();
    final value = await showDatePicker(
        context: context,
        initialDate: _cierre ?? ahora.add(const Duration(days: 7)),
        firstDate: DateTime(ahora.year, ahora.month, ahora.day),
        lastDate: ahora.add(const Duration(days: 730)));
    if (value != null && mounted) {
      setState(
          () => _cierre = DateTime(value.year, value.month, value.day, 23, 59));
    }
  }

  Future<void> _publicar() async {
    if (_ocupado || !_form.currentState!.validate()) return;
    if (_cierre == null || !_cierre!.isAfter(DateTime.now())) {
      setState(() => _error = 'Elige una fecha de cierre futura.');
      return;
    }
    final monto = textoACentavos(_monto.text)!;
    final tasa = double.parse(_tasa.text.trim().replaceAll(',', '.'));
    final confirmar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Publicar oferta'),
                content: Text(
                    'Solicitarás ${money(monto, _factura!.moneda)} para la factura ${_factura!.numero}, con tasa anual de ${tasa.toStringAsFixed(2)}% y cierre el ${fecha(_cierre)}.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Volver')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Confirmar publicación'))
                ]));
    if (!mounted || confirmar != true) return;
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final oferta = await InversionService(widget.api).crearOferta(
          facturaId: _facturaId!,
          montoCentavos: monto,
          tasaAnual: tasa,
          fechaCierre: _cierre!);
      if (mounted) Navigator.pop(context, oferta);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is ApiException
            ? error.message
            : 'No se pudo confirmar la publicación. Consulta el catálogo antes de volver a enviarla.');
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_ocupado,
      child: Scaffold(
          appBar: AppBar(title: const Text('Publicar oferta')),
          body: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: ListView(padding: const EdgeInsets.all(24), children: [
                    const PageHeader(
                        title: 'Una factura, nuevas posibilidades',
                        subtitle:
                            'Publica una oferta a partir de una factura disponible con DTE verificado.'),
                    const SizedBox(height: 26),
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Form(
                                key: _form,
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (_cargando)
                                        const LinearProgressIndicator(),
                                      if (!_cargando && _facturas.isEmpty)
                                        const Padding(
                                            padding:
                                                EdgeInsets.only(bottom: 16),
                                            child: Text(
                                                'Aún no hay facturas disponibles y vigentes. Registra una factura y solicita la verificación de su DTE.')),
                                      DropdownButtonFormField<String>(
                                          initialValue: _facturaId,
                                          isExpanded: true,
                                          decoration: const InputDecoration(
                                              labelText: 'Factura disponible'),
                                          items: [
                                            for (final f in _facturas)
                                              DropdownMenuItem(
                                                  value: f.id,
                                                  child: Text(
                                                      '${f.numero} · ${money(f.montoPendienteCentavos, f.moneda)}',
                                                      overflow: TextOverflow
                                                          .ellipsis))
                                          ],
                                          onChanged: _ocupado
                                              ? null
                                              : (value) => setState(
                                                  () => _facturaId = value),
                                          validator: (value) => value == null
                                              ? 'Selecciona una factura'
                                              : null),
                                      if (_hayMas)
                                        TextButton(
                                            onPressed: _cargando || _ocupado
                                                ? null
                                                : () => _cargar(mas: true),
                                            child: const Text(
                                                'Cargar más facturas')),
                                      if (_factura != null) ...[
                                        const SizedBox(height: 12),
                                        Text(
                                            'Vence el ${fecha(_factura!.fechaVencimiento)}',
                                            style: const TextStyle(
                                                color: AppColors.muted))
                                      ],
                                      const SizedBox(height: 22),
                                      TextFormField(
                                          controller: _monto,
                                          enabled: !_ocupado,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          decoration: const InputDecoration(
                                              labelText: 'Monto objetivo (USD)',
                                              helperText:
                                                  'Hasta dos decimales'),
                                          validator: (value) {
                                            final cents =
                                                textoACentavos(value ?? '');
                                            if (cents == null) {
                                              return 'Escribe un monto válido mayor que cero';
                                            }
                                            if (_factura != null &&
                                                cents >
                                                    _factura!
                                                        .montoPendienteCentavos) {
                                              return 'El objetivo supera el saldo de la factura';
                                            }
                                            return null;
                                          }),
                                      const SizedBox(height: 22),
                                      TextFormField(
                                          controller: _tasa,
                                          enabled: !_ocupado,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          decoration: const InputDecoration(
                                              labelText:
                                                  'Tasa de rendimiento anual (%)'),
                                          validator: (value) {
                                            final rate = double.tryParse(
                                                (value ?? '')
                                                    .replaceAll(',', '.'));
                                            return rate == null ||
                                                    !rate.isFinite ||
                                                    rate < 0 ||
                                                    rate > 100
                                                ? 'Usa una tasa entre 0 y 100'
                                                : null;
                                          }),
                                      const SizedBox(height: 20),
                                      OutlinedButton.icon(
                                          onPressed: _ocupado ? null : _fecha,
                                          icon: const Icon(
                                              Icons.calendar_today_outlined),
                                          label: Text(_cierre == null
                                              ? 'Elegir fecha de cierre'
                                              : 'Cierre: ${fecha(_cierre)}')),
                                      const SizedBox(height: 8),
                                      const Text(
                                          'La oferta cerrará al final del día seleccionado.',
                                          style: TextStyle(
                                              color: AppColors.muted,
                                              fontSize: 12)),
                                      if (_error != null) ...[
                                        const SizedBox(height: 18),
                                        Text(_error!,
                                            style: const TextStyle(
                                                color: AppColors.error)),
                                        if (_facturas.isEmpty)
                                          TextButton(
                                              onPressed:
                                                  _cargando ? null : _cargar,
                                              child: const Text(
                                                  'Reintentar carga'))
                                      ],
                                      const SizedBox(height: 24),
                                      FilledButton(
                                          onPressed: _ocupado ||
                                                  _cargando ||
                                                  _facturas.isEmpty
                                              ? null
                                              : _publicar,
                                          child: Text(_ocupado
                                              ? 'Publicando...'
                                              : 'Revisar oferta')),
                                    ])))),
                  ])))));
}
