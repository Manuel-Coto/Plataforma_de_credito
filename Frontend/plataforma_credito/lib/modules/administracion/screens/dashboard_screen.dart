import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:plataforma_credito/core/format.dart';
import 'package:plataforma_credito/modules/administracion/providers/reportes_provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<ReportesProvider>().cargar());
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ReportesProvider>();
    final r = p.resumen;
    return Scaffold(
      appBar: AppBar(title: const Text('Panel de administración'), actions: [
        IconButton(tooltip: 'Actualizar', onPressed: p.cargar, icon: const Icon(Icons.refresh)),
      ]),
      body: p.cargando
          ? const Center(child: CircularProgressIndicator())
          : p.error != null
              ? Center(child: Text(p.error!))
              : r == null
                  ? const Center(child: Text('Sin datos todavía.'))
                  : ListView(padding: const EdgeInsets.all(16), children: [
                      Wrap(spacing: 12, runSpacing: 12, children: [
                        _kpi('Operaciones', '${r.totalOperaciones}'),
                        _kpi('Monto total', money(r.montoTotalCentavos)),
                        _kpi('Empresas verificadas', '${r.empresasVerificadas}'),
                        _kpi('Facturas pendientes', '${r.facturasPendientes}'),
                      ]),
                      const SizedBox(height: 24),
                      Text('Operaciones por estado',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      for (final e in r.porEstado.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(children: [
                            SizedBox(width: 120, child: Text(estadoLegible(e.key))),
                            Expanded(
                              child: LinearProgressIndicator(
                                value: r.totalOperaciones == 0
                                    ? 0
                                    : e.value / r.totalOperaciones,
                                minHeight: 10,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text('${e.value}'),
                          ]),
                        ),
                    ]),
    );
  }

  Widget _kpi(String t, String v) => SizedBox(
        width: 220,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t),
              const SizedBox(height: 8),
              Text(v, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}
