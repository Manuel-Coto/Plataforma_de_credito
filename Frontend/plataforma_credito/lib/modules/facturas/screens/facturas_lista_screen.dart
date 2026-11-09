import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/estado_carga.dart';
import '../../../core/theme/credito_theme.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/page_header.dart';
import '../../../widgets/vista_error.dart';
import '../providers/facturas_provider.dart';
import '../widgets/factura_card.dart';
import '../widgets/filtro_estados.dart';
import 'factura_form_screen.dart';
import '../../usuarios/providers/sesion_provider.dart';

class FacturasListaScreen extends StatefulWidget {
  const FacturasListaScreen({super.key});
  @override
  State<FacturasListaScreen> createState() => _FacturasListaScreenState();
}

class _FacturasListaScreenState extends State<FacturasListaScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<FacturasProvider>().cargar();
    });
  }

  void _nuevaFactura() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const FacturaFormScreen()));

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FacturasProvider>();
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: PageHeader(
              eyebrow: 'TU ACTIVIDAD',
              title: 'Facturas',
              subtitle: 'Tus facturas, organizadas y siempre a la mano.',
              action: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton.outlined(
                    tooltip: 'Actualizar',
                    onPressed: provider.estadoCarga == EstadoCarga.cargando
                        ? null
                        : provider.cargar,
                    icon: const Icon(Icons.refresh_rounded, size: 21)),
                if (context.watch<SesionProvider>().usuario?['rol'] ==
                    'pyme') ...[
                  const SizedBox(width: 10),
                  FilledButton.icon(
                      onPressed: _nuevaFactura,
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text('Nueva factura')),
                ],
              ]),
            ),
          ),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text('Filtrar por estado',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: AppColors.muted))),
          const SizedBox(height: 10),
          FiltroEstados(
              seleccionado: provider.filtro, onCambio: provider.filtrarPor),
          const SizedBox(height: 12),
          Expanded(child: _contenido(provider)),
        ]),
      ),
    );
  }

  Widget _contenido(FacturasProvider provider) {
    switch (provider.estadoCarga) {
      case EstadoCarga.inicial:
      case EstadoCarga.cargando:
        return const Center(child: CircularProgressIndicator());
      case EstadoCarga.error:
        return VistaError(
            mensaje: provider.mensajeError ?? 'Ocurrió un error',
            onReintentar: provider.cargar);
      case EstadoCarga.listo:
        if (provider.facturas.isEmpty) {
          return EmptyState(
            icon: Icons.receipt_long_outlined,
            title: provider.filtro == null
                ? 'Aquí comienza tu historial'
                : 'No hay facturas en este estado',
            message: provider.filtro == null
                ? 'Registra tu primera factura para consultar sus detalles y seguir su estado.'
                : 'Prueba con otro filtro para explorar tus facturas.',
          );
        }
        return RefreshIndicator(
          onRefresh: provider.cargar,
          child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
              itemCount: provider.facturas.length + 1,
              itemBuilder: (context, i) => i < provider.facturas.length
                  ? FacturaCard(factura: provider.facturas[i])
                  : _paginacion(provider)),
        );
    }
  }

  Widget _paginacion(FacturasProvider provider) => Column(children: [
        if (provider.errorMas != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(provider.errorMas!,
                  style: const TextStyle(color: AppColors.error))),
        if (provider.hayMas)
          OutlinedButton.icon(
              onPressed: provider.cargandoMas ? null : provider.cargarMas,
              icon: provider.cargandoMas
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.expand_more),
              label: Text(provider.cargandoMas
                  ? 'Cargando...'
                  : provider.errorMas == null
                      ? 'Cargar más facturas'
                      : 'Reintentar página')),
        if (!provider.hayMas && provider.facturas.isNotEmpty)
          const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Has llegado al final de la consulta.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12))),
      ]);
}
