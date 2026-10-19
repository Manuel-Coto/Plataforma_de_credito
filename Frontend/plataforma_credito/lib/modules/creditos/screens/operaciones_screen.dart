import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:plataforma_credito/core/format.dart';
import 'package:plataforma_credito/modules/creditos/providers/operaciones_provider.dart';

class OperacionesScreen extends StatefulWidget {
  const OperacionesScreen({super.key});
  @override
  State<OperacionesScreen> createState() => _OperacionesScreenState();
}

class _OperacionesScreenState extends State<OperacionesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<OperacionesProvider>().cargar());
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<OperacionesProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Créditos y pagos'), actions: [
        IconButton(
            tooltip: 'Actualizar',
            onPressed: p.cargando ? null : p.cargar,
            icon: const Icon(Icons.refresh)),
      ]),
      body: Column(children: [
        if (p.estados.isNotEmpty)
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _chip('Todas', p.filtro == null, () => p.setFiltro(null)),
                for (final e in p.estados)
                  _chip(estadoLegible(e), p.filtro == e, () => p.setFiltro(e)),
              ],
            ),
          ),
        Expanded(child: _cuerpo(p)),
      ]),
    );
  }

  Widget _chip(String t, bool sel, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(label: Text(t), selected: sel, onSelected: (_) => onTap()),
      );

  Widget _cuerpo(OperacionesProvider p) {
    if (p.cargando) return const Center(child: CircularProgressIndicator());
    if (p.error != null) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(p.error!),
        const SizedBox(height: 12),
        FilledButton(onPressed: p.cargar, child: const Text('Reintentar')),
      ]));
    }
    if (p.operaciones.isEmpty) {
      return const Center(child: Text('Aún no hay operaciones. Aparecerán cuando se acepte una oferta.'));
    }
    return RefreshIndicator(
      onRefresh: p.cargar,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: p.operaciones.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final o = p.operaciones[i];
          return Card(
            child: ListTile(
              title: Text('Factura ${o.facturaId}'),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${money(o.montoCentavos, o.moneda)} · vence ${fecha(o.vencimiento)}'),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: o.progreso),
                ]),
              ),
              trailing: Text(estadoLegible(o.estado)),
              onTap: () => context.push('/operaciones/${o.id}', extra: o),
            ),
          );
        },
      ),
    );
  }
}
