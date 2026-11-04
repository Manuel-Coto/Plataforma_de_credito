import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:plataforma_credito/modules/empresas/providers/empresas_admin_provider.dart';
import 'package:plataforma_credito/modules/usuarios/providers/sesion_provider.dart';

class EmpresasPendientesScreen extends StatelessWidget {
  const EmpresasPendientesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<SesionProvider>().api;
    return ChangeNotifierProvider(
      create: (_) => EmpresasAdminProvider(api)..cargar(),
      child: const _Lista(),
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista();

  Future<String?> _pedirMotivo(BuildContext context) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Motivo del rechazo'),
        content: TextField(controller: c, maxLines: 3, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (c.text.trim().isNotEmpty) Navigator.pop(context, c.text.trim());
            },
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<EmpresasAdminProvider>();
    if (p.cargando) return const Center(child: CircularProgressIndicator());
    if (p.error != null) return Center(child: Text(p.error!));
    if (p.pendientes.isEmpty) {
      return const Center(child: Text('No hay empresas pendientes de revisión.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final e in p.pendientes)
          Card(
            child: ListTile(
              title: Text('${e['nombre']}'),
              subtitle: Text('NIT: ${e['nit']}  ·  ${e['correo']}'),
              trailing: Wrap(spacing: 8, children: [
                OutlinedButton(
                  onPressed: () async {
                    final motivo = await _pedirMotivo(context);
                    if (motivo != null) p.rechazar('${e['id']}', motivo);
                  },
                  child: const Text('Rechazar'),
                ),
                FilledButton(
                  onPressed: () => p.aprobar('${e['id']}'),
                  child: const Text('Aprobar'),
                ),
              ]),
            ),
          ),
      ],
    );
  }
}