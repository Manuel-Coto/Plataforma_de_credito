import 'package:flutter/material.dart';
import '../../../models/estado_factura.dart';

/// Filtro utilizado por la lista; el provider conserva la consulta y su estado.
class FiltroEstados extends StatelessWidget {
  const FiltroEstados({super.key, required this.seleccionado, required this.onCambio});

  final EstadoFactura? seleccionado;
  final ValueChanged<EstadoFactura?> onCambio;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(children: [
      Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
        label: const Text('Todas'), selected: seleccionado == null,
        onSelected: (_) => onCambio(null),
      )),
      for (final estado in EstadoFactura.values)
        Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
          label: Text(estado.etiqueta), selected: seleccionado == estado,
          onSelected: (_) => onCambio(estado),
        )),
    ]),
  );
}
