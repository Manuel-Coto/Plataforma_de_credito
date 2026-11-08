import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/format.dart';
import '../../../core/theme/credito_theme.dart';
import '../../../models/operacion.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/page_header.dart';
import '../../../widgets/vista_error.dart';
import '../providers/operaciones_provider.dart';
import 'operacion_detalle_screen.dart';

class OperacionesScreen extends StatefulWidget {
  const OperacionesScreen({super.key});
  @override
  State<OperacionesScreen> createState() => _OperacionesScreenState();
}

class _OperacionesScreenState extends State<OperacionesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<OperacionesProvider>().cargar();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OperacionesProvider>();
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: PageHeader(
                eyebrow: 'EN MOVIMIENTO',
                title: 'Créditos y pagos',
                subtitle:
                    'Sigue cada operación y conoce el avance de tus pagos.',
                action: OutlinedButton.icon(
                    onPressed: provider.cargando ? null : provider.cargar,
                    icon: const Icon(Icons.refresh_rounded, size: 19),
                    label: const Text('Actualizar'))),
          ),
          if (provider.estados.isNotEmpty)
            SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
                child: Row(children: [
                  _chip('Todas', provider.filtro == null,
                      () => provider.setFiltro(null)),
                  for (final estado in provider.estados)
                    _chip(estadoLegible(estado), provider.filtro == estado,
                        () => provider.setFiltro(estado)),
                ])),
          Expanded(child: _cuerpo(provider)),
        ]),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
          label: Text(label), selected: selected, onSelected: (_) => onTap()));

  Widget _cuerpo(OperacionesProvider provider) {
    if (provider.cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.error != null) {
      return VistaError(
          mensaje: provider.error!, onReintentar: provider.cargar);
    }
    if (provider.operaciones.isEmpty) {
      return EmptyState(
          icon: Icons.account_balance_wallet_outlined,
          title: provider.filtro == null
              ? 'Tus próximos pasos, aquí'
              : 'No hay operaciones en este estado',
          message: provider.filtro == null
              ? 'Las operaciones aparecerán cuando se acepte una oferta. Aquí podrás seguir sus pagos y vencimientos.'
              : 'Selecciona otro estado para consultar tus operaciones.');
    }
    return RefreshIndicator(
      onRefresh: provider.cargar,
      child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          itemCount: provider.operaciones.length,
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (_, i) =>
              _OperacionCard(operacion: provider.operaciones[i])),
    );
  }
}

class _OperacionCard extends StatelessWidget {
  const _OperacionCard({required this.operacion});
  final Operacion operacion;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final o = operacion;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => OperacionDetalleScreen(operacion: o))),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                      color: AppColors.softPrimary,
                      borderRadius: BorderRadius.circular(13)),
                  child: const Icon(Icons.payments_outlined,
                      color: AppColors.primary, size: 22)),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Factura ${o.facturaId}', style: texto.titleMedium),
                    const SizedBox(height: 5),
                    Text('Vence ${fecha(o.vencimiento)}',
                        style:
                            texto.bodySmall?.copyWith(color: AppColors.muted)),
                  ])),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ]),
            const SizedBox(height: 18),
            Wrap(
                spacing: 18,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(money(o.montoCentavos, o.moneda),
                      style: texto.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: AppColors.softPrimary,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(estadoLegible(o.estado),
                          style: texto.labelMedium
                              ?.copyWith(color: AppColors.primary))),
                ]),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                  child: Text('Pagado ${money(o.pagadoCentavos, o.moneda)}',
                      style:
                          texto.bodySmall?.copyWith(color: AppColors.muted))),
              Text('${(o.progreso * 100).round()}%',
                  style: texto.labelMedium?.copyWith(color: AppColors.primary)),
            ]),
            const SizedBox(height: 9),
            ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                    value: o.progreso,
                    minHeight: 7,
                    backgroundColor: AppColors.softPrimary)),
          ]),
        ),
      ),
    );
  }
}
