import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/format.dart';
import '../../../core/theme/credito_theme.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/page_header.dart';
import '../../../widgets/vista_error.dart';
import '../providers/reportes_provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ReportesProvider>().cargar();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReportesProvider>();
    final resumen = provider.resumen;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: PageHeader(
                  eyebrow: 'VISTA GENERAL',
                  title: 'Panel de administración',
                  subtitle: 'Una mirada clara a la actividad de la plataforma.',
                  action: OutlinedButton.icon(
                      onPressed: provider.cargando ? null : provider.cargar,
                      icon: const Icon(Icons.refresh_rounded, size: 19),
                      label: const Text('Actualizar')))),
          Expanded(
            child: provider.cargando
                ? const Center(child: CircularProgressIndicator())
                : provider.error != null
                    ? VistaError(
                        mensaje: provider.error!, onReintentar: provider.cargar)
                    : resumen == null
                        ? const EmptyState(
                            icon: Icons.bar_chart_rounded,
                            title: 'La actividad empieza aquí',
                            message:
                                'Cuando haya operaciones, podrás consultar el resumen de la plataforma.')
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                            children: [
                                LayoutBuilder(builder: (context, constraints) {
                                  final columns = constraints.maxWidth >= 920
                                      ? 4
                                      : constraints.maxWidth >= 450
                                          ? 2
                                          : 1;
                                  final width = (constraints.maxWidth -
                                          (columns - 1) * 16) /
                                      columns;
                                  return Wrap(
                                      spacing: 16,
                                      runSpacing: 16,
                                      children: [
                                        _kpi(
                                            width,
                                            'Operaciones',
                                            '${resumen.totalOperaciones}',
                                            Icons.swap_horiz_rounded,
                                            'En la plataforma'),
                                        _kpi(
                                            width,
                                            'Monto total',
                                            money(resumen.montoTotalCentavos),
                                            Icons
                                                .account_balance_wallet_outlined,
                                            'En operaciones'),
                                        _kpi(
                                            width,
                                            'Empresas verificadas',
                                            '${resumen.empresasVerificadas}',
                                            Icons.business_outlined,
                                            'Con revisión completa'),
                                        _kpi(
                                            width,
                                            'Facturas pendientes',
                                            '${resumen.facturasPendientes}',
                                            Icons.receipt_long_outlined,
                                            'Por verificar'),
                                      ]);
                                }),
                                const SizedBox(height: 24),
                                Card(
                                  margin: EdgeInsets.zero,
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('El estado de las operaciones',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge),
                                          const SizedBox(height: 6),
                                          const Text(
                                              'Distribución según su estado actual.',
                                              style: TextStyle(
                                                  color: AppColors.muted)),
                                          const SizedBox(height: 24),
                                          if (resumen.porEstado.isEmpty)
                                            const Padding(
                                                padding: EdgeInsets.symmetric(
                                                    vertical: 20),
                                                child: Text(
                                                    'Aún no hay operaciones para mostrar.',
                                                    style: TextStyle(
                                                        color:
                                                            AppColors.muted))),
                                          for (final estado
                                              in resumen.porEstado.entries)
                                            Padding(
                                                padding: const EdgeInsets.only(
                                                    bottom: 20),
                                                child: Column(children: [
                                                  Row(children: [
                                                    Expanded(
                                                        child: Text(
                                                            estadoLegible(
                                                                estado.key))),
                                                    const SizedBox(width: 12),
                                                    Text('${estado.value}',
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700)),
                                                  ]),
                                                  const SizedBox(height: 10),
                                                  ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10),
                                                      child: LinearProgressIndicator(
                                                          value: resumen
                                                                      .totalOperaciones <=
                                                                  0
                                                              ? 0
                                                              : (estado.value /
                                                                      resumen
                                                                          .totalOperaciones)
                                                                  .clamp(
                                                                      0.0, 1.0)
                                                                  .toDouble(),
                                                          minHeight: 9,
                                                          backgroundColor:
                                                              AppColors
                                                                  .softPrimary)),
                                                ])),
                                        ]),
                                  ),
                                ),
                              ]),
          ),
        ]),
      ),
    );
  }

  Widget _kpi(double width, String title, String value, IconData icon,
          String detail) =>
      SizedBox(
        width: width,
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 13))),
                const SizedBox(width: 8),
                Icon(icon, color: AppColors.primary, size: 21),
              ]),
              const SizedBox(height: 24),
              FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1))),
              const SizedBox(height: 7),
              Text(detail,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
          ),
        ),
      );
}
