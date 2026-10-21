import 'package:flutter/material.dart';
import 'package:plataforma_credito/core/format.dart';
import 'package:plataforma_credito/models/operacion.dart';

class OperacionDetalleScreen extends StatelessWidget {
  const OperacionDetalleScreen({super.key, required this.operacion});
  final Operacion operacion;

  @override
  Widget build(BuildContext context) {
    final o = operacion;
    return Scaffold(
      appBar: AppBar(title: Text('Factura ${o.facturaId}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(money(o.montoCentavos, o.moneda),
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text('${estadoLegible(o.estado)} · vence ${fecha(o.vencimiento)}'),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: o.progreso),
        const SizedBox(height: 4),
        Text('Pagado ${money(o.pagadoCentavos, o.moneda)} de ${money(o.montoCentavos, o.moneda)}'),
        const SizedBox(height: 24),
        Text('Pagos (simulados)', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (o.pagos.isEmpty) const Text('Todavía no se registran pagos.'),
        for (final p in o.pagos)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(p.estado == 'pagado' ? Icons.check_circle : Icons.schedule),
            title: Text(money(p.montoCentavos, o.moneda)),
            subtitle: Text(fecha(p.fecha)),
            trailing: Text(estadoLegible(p.estado)),
          ),
      ]),
    );
  }
}
