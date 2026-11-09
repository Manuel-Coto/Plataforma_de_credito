import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/estado_factura.dart';
import '../../../services/factura_service.dart';
import '../../../services/api_client.dart';
import '../../usuarios/providers/sesion_provider.dart';
import '../providers/facturas_provider.dart';
import '../../../models/factura.dart';
import '../../../widgets/fila_dato.dart';
import '../../../core/utils/formato.dart';
import '../../../widgets/seccion_card.dart';

class FacturaDetalleScreen extends StatefulWidget {
  const FacturaDetalleScreen({super.key, required this.factura});

  final Factura factura;

  @override
  State<FacturaDetalleScreen> createState() => _FacturaDetalleScreenState();
}

class _FacturaDetalleScreenState extends State<FacturaDetalleScreen> {
  late Factura factura = widget.factura;
  final _sello = TextEditingController();
  bool _ocupado = false;
  bool _actual = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _consultar();
    });
  }

  @override
  void dispose() {
    _sello.dispose();
    super.dispose();
  }

  FacturaService get _servicio =>
      FacturaService(context.read<SesionProvider>().api);

  Future<void> _consultar({String? aviso}) async {
    setState(() {
      _ocupado = true;
      _actual = false;
      _error = aviso;
    });
    try {
      final nueva = await _servicio.obtener(factura.id);
      if (mounted) {
        setState(() {
          factura = nueva;
          _actual = true;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo actualizar la factura.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _verificar() async {
    if (_ocupado || !_actual) return;
    if (_sello.text.trim().isEmpty) {
      setState(() => _error = 'Escribe el sello de recepción del DTE.');
      return;
    }
    final confirmar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('¿Confirmar revisión del DTE?'),
              content: const Text(
                  'La factura quedará disponible para financiamiento. Esta es una revisión interna; no consulta ni certifica el documento ante Hacienda.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Confirmar verificación'))
              ],
            ));
    if (confirmar != true || !mounted || _ocupado) return;
    final provider = context.read<FacturasProvider>();
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final nueva = await _servicio.verificarDte(factura.id, _sello.text);
      if (!mounted) return;
      setState(() {
        factura = nueva;
        _sello.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('DTE verificado. La factura está disponible.')));
      await provider.cargar();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 409) {
        await _consultar(
            aviso:
                'La factura cambió. Revisa los datos actualizados antes de continuar.');
      } else {
        setState(() {
          _error = e.message;
          _actual = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _actual = false;
          _error =
              'No se pudo confirmar el resultado. Actualiza antes de continuar.';
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
    return Scaffold(
      appBar: AppBar(title: Text('Factura ${factura.numero}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_ocupado) const LinearProgressIndicator(),
          if (_error != null &&
              _error != 'Escribe el sello de recepción del DTE.')
            Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                  onPressed: _ocupado ? null : _consultar,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualizar factura'))),
          SeccionCard(
            titulo: 'General',
            children: [
              FilaDato(etiqueta: 'Número', valor: factura.numero),
              FilaDato(etiqueta: 'Moneda', valor: factura.moneda),
              FilaDato(etiqueta: 'Estado', valor: factura.estado.etiqueta),
            ],
          ),
          SeccionCard(
            titulo: 'Fechas',
            children: [
              FilaDato(
                etiqueta: 'Emisión',
                valor: Formato.fecha(factura.fechaEmision),
              ),
              FilaDato(
                etiqueta: 'Vencimiento',
                valor: Formato.fecha(factura.fechaVencimiento),
              ),
            ],
          ),
          SeccionCard(
            titulo: 'Montos',
            children: [
              FilaDato(
                etiqueta: 'Total',
                valor: Formato.dinero(
                  factura.montoTotalCentavos,
                  factura.moneda,
                ),
              ),
              FilaDato(
                etiqueta: 'Financiado',
                valor: Formato.dinero(
                  factura.montoFinanciadoCentavos,
                  factura.moneda,
                ),
              ),
              FilaDato(
                etiqueta: 'Pendiente',
                valor: Formato.dinero(
                  factura.montoPendienteCentavos,
                  factura.moneda,
                ),
              ),
            ],
          ),
          SeccionCard(
            titulo: 'Documento tributario (DTE)',
            children: [
              FilaDato(
                etiqueta: 'Código de generación',
                valor: factura.dte.codigoGeneracion,
              ),
              FilaDato(
                etiqueta: 'Verificado',
                valor: factura.dte.verificado ? 'Sí' : 'No',
              ),
              FilaDato(
                etiqueta: 'Sello de recepción',
                valor: factura.dte.selloRecepcion ?? 'Pendiente',
              ),
              if (factura.dte.fechaVerificacion != null)
                FilaDato(
                  etiqueta: 'Fecha de verificación',
                  valor: Formato.fecha(factura.dte.fechaVerificacion!),
                ),
            ],
          ),
          if (admin &&
              !factura.dte.verificado &&
              factura.estado == EstadoFactura.pendienteVerificacion)
            SeccionCard(titulo: 'Revisión administrativa', children: [
              const Text(
                  'Revisa el documento e ingresa su sello de recepción. Esta revisión interna no realiza una validación automática ante Hacienda.'),
              const SizedBox(height: 20),
              TextField(
                  controller: _sello,
                  enabled: !_ocupado,
                  decoration: InputDecoration(
                      errorText: _sello.text.trim().isEmpty &&
                              _error == 'Escribe el sello de recepción del DTE.'
                          ? _error
                          : null,
                      labelText: 'Sello de recepción',
                      prefixIcon: const Icon(Icons.verified_outlined))),
              const SizedBox(height: 16),
              FilledButton.icon(
                  onPressed: _ocupado || !_actual ? null : _verificar,
                  icon: const Icon(Icons.check),
                  label: const Text('Verificar DTE')),
            ]),
        ],
      ),
    );
  }
}
