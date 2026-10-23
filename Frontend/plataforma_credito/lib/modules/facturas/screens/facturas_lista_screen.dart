import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/estado_carga.dart';
import '../../../widgets/vista_error.dart';
import '../providers/facturas_provider.dart';
import '../widgets/factura_card.dart';

// StatefulWidget, necesita ejecutar algo UNA vez al abrirse:
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
      if (!mounted) return;
      context.read<FacturasProvider>().cargar();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FacturasProvider>();

    return Column(
      children: [
        // Encabezado propio: título a la izquierda, botón a la derecha.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(
            children: [
              Text(
                'Facturas',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Actualizar',
                icon: const Icon(Icons.refresh),
                // null deshabilita el botón mientras ya está cargando.
                onPressed: provider.estadoCarga == EstadoCarga.cargando
                    ? null
                    : provider.cargar,
              ),
            ],
          ),
        ),
        // Expanded: el contenido ocupa todo el alto que queda debajo.
        Expanded(child: _contenido(provider)),
      ],
    );
  }

  // Un caso por cada estado posible. Dart verifica que no falte ninguno.
  Widget _contenido(FacturasProvider provider) {
    switch (provider.estadoCarga) {
      case EstadoCarga.inicial:
      case EstadoCarga.cargando:
        return const Center(child: CircularProgressIndicator());

      case EstadoCarga.error:
        return VistaError(
          mensaje: provider.mensajeError ?? 'Ocurrió un error',
          onReintentar: provider.cargar,
        );

      case EstadoCarga.listo:
        if (provider.facturas.isEmpty) {
          return const Center(child: Text('No hay facturas registradas'));
        }
        // En escritorio, limitamos el ancho para que las tarjetas no se
        // estiren por toda la ventana.
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: provider.facturas.length,
              // Construye solo las tarjetas visibles, no toda la lista.
              itemBuilder: (context, i) =>
                  FacturaCard(factura: provider.facturas[i]),
            ),
          ),
        );
    }
  }
}