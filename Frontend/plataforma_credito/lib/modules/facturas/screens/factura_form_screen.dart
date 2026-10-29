import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formato.dart';
import '../../../models/crear_factura.dart';
import '../../../models/empresa_opcion.dart';
import '../../../services/api_client.dart';
import '../providers/facturas_provider.dart';

class FacturaFormScreen extends StatefulWidget {
  const FacturaFormScreen({super.key});

  @override
  State<FacturaFormScreen> createState() => _FacturaFormScreenState();
}

class _FacturaFormScreenState extends State<FacturaFormScreen> {
  // Llave para validar todo el formulario de una vez.
  final _formKey = GlobalKey<FormState>();

  // Un controller por campo de texto: permite leer (y cambiar) lo escrito.
  final _numero = TextEditingController();
  final _codigo = TextEditingController();
  final _monto = TextEditingController();
  final _emision = TextEditingController();
  final _vencimiento = TextEditingController();

  late final Future<List<EmpresaOpcion>> _empresas;
  EmpresaOpcion? _empresa;
  DateTime? _fechaEmision;
  DateTime? _fechaVencimiento;
  bool _enviando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _empresas = context.read<FacturasProvider>().cargarEmpresas();
  }

  @override
  void dispose() {
    // Los controllers hay que liberarlos al cerrar la pantalla.
    _numero.dispose();
    _codigo.dispose();
    _monto.dispose();
    _emision.dispose();
    _vencimiento.dispose();
    super.dispose();
  }

  /// "2500.50" -> 250050. Devuelve null si no es un monto válido.
  int? _aCentavos(String texto) {
    final valor = double.tryParse(texto.trim());
    if (valor == null || valor <= 0) return null;
    return (valor * 100).round();
  }

  Future<void> _elegirFecha({
    required TextEditingController campo,
    required ValueChanged<DateTime> alElegir,
  }) async {
    final ahora = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: ahora,
      firstDate: DateTime(ahora.year - 2),
      lastDate: DateTime(ahora.year + 3),
    );
    if (fecha == null) return; // el usuario canceló
    alElegir(fecha);
    campo.text = Formato.fecha(fecha);
  }

  Future<void> _guardar() async {
    // validate() ejecuta el validator de cada campo; false si alguno falla.
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      await context.read<FacturasProvider>().crear(
        CrearFactura(
          empresaId: _empresa!.id,
          numero: _numero.text.trim(),
          codigoGeneracion: _codigo.text.trim(),
          moneda: 'USD',
          montoTotalCentavos: _aCentavos(_monto.text)!,
          fechaEmision: _fechaEmision!,
          fechaVencimiento: _fechaVencimiento!,
        ),
      );
      if (!mounted) return;
      Navigator.pop(context); // volver a la lista
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva factura')),
      // FutureBuilder: dibuja según el estado de un Future (cargando/error/listo).
      body: FutureBuilder<List<EmpresaOpcion>>(
        future: _empresas,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final e = snapshot.error;
            return Center(
              child: Text(e is ApiException
                  ? e.message
                  : 'No se pudieron cargar las empresas'),
            );
          }
          final activas = snapshot.data!.where((e) => e.activa).toList();
          if (activas.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No tienes empresas activas. Un administrador debe '
                      'aprobar tu empresa antes de registrar facturas.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _formulario(activas);
        },
      ),
    );
  }

  Widget _formulario(List<EmpresaOpcion> empresas) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<EmpresaOpcion>(
                decoration: const InputDecoration(
                  labelText: 'Empresa',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final e in empresas)
                    DropdownMenuItem(value: e, child: Text(e.nombre)),
                ],
                onChanged: (v) => setState(() => _empresa = v),
                validator: (v) => v == null ? 'Elige una empresa' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _numero,
                decoration: const InputDecoration(
                  labelText: 'Número de factura',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'El número es obligatorio'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _codigo,
                decoration: const InputDecoration(
                  labelText: 'Código de generación del DTE',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'El código del DTE es obligatorio';
                  if (t.length > 100) return 'Máximo 100 caracteres';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _monto,
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Monto total (USD)',
                  helperText: 'Ejemplo: 2500.50',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => _aCentavos(v ?? '') == null
                    ? 'Escribe un monto mayor que cero'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emision,
                readOnly: true, // no se escribe: se elige en el calendario
                decoration: const InputDecoration(
                  labelText: 'Fecha de emisión',
                  suffixIcon: Icon(Icons.calendar_today),
                  border: OutlineInputBorder(),
                ),
                onTap: () => _elegirFecha(
                  campo: _emision,
                  alElegir: (f) => _fechaEmision = f,
                ),
                validator: (_) =>
                _fechaEmision == null ? 'Elige la fecha de emisión' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _vencimiento,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Fecha de vencimiento',
                  suffixIcon: Icon(Icons.calendar_today),
                  border: OutlineInputBorder(),
                ),
                onTap: () => _elegirFecha(
                  campo: _vencimiento,
                  alElegir: (f) => _fechaVencimiento = f,
                ),
                validator: (_) {
                  if (_fechaVencimiento == null) {
                    return 'Elige la fecha de vencimiento';
                  }
                  if (_fechaEmision != null &&
                      _fechaVencimiento!.isBefore(_fechaEmision!)) {
                    return 'No puede ser anterior a la emisión';
                  }
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _enviando ? null : _guardar,
                child: _enviando
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Text('Registrar factura'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}