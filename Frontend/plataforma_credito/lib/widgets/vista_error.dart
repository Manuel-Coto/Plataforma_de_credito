import 'package:flutter/material.dart';
import 'empty_state.dart';

class VistaError extends StatelessWidget {
  const VistaError(
      {super.key, required this.mensaje, required this.onReintentar});
  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) => EmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'No pudimos cargar la información',
      message: mensaje,
      action: OutlinedButton.icon(
          onPressed: onReintentar,
          icon: const Icon(Icons.refresh_rounded, size: 19),
          label: const Text('Reintentar')));
}
