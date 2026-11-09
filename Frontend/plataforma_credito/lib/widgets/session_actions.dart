import 'package:flutter/material.dart';

import '../modules/usuarios/providers/sesion_provider.dart';

Future<void> confirmarCierreSesion(
    BuildContext context, SesionProvider sesion) async {
  final offline = sesion.api.offline;
  if (offline.syncing) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Espera a que termine la sincronización para cerrar sesión.')));
    return;
  }
  if (offline.operations.isNotEmpty) {
    final salir = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Hay cambios sin sincronizar'),
              content: Text(
                  'Tienes ${offline.operations.length} cambios guardados en este equipo. Cerrar sesión eliminará sus copias locales y las consultas guardadas. No deshace cambios que el servidor ya haya recibido. Puedes volver y sincronizarlos primero.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Volver')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Eliminar y cerrar sesión')),
              ],
            ));
    if (salir != true || !context.mounted) return;
  }
  sesion.cerrar();
}
