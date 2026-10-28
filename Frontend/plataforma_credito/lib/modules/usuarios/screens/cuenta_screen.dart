import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sesion_provider.dart';

class CuentaScreen extends StatelessWidget {
  const CuentaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sesion = context.watch<SesionProvider>();
    final usuario = sesion.usuario!;
    final rol = switch (usuario['rol']) {
      'pyme' => 'PYME',
      'inversionista' => 'Inversionista',
      'administrador' => 'Administrador',
      _ => usuario['rol'] as String,
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 32),
      child: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Mi cuenta',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700, color: const Color(0xFF172B4D))),
          const SizedBox(height: 8),
          const Text('Tu sesión está activa.',
              style: TextStyle(color: Color(0xFF65758B))),
          const SizedBox(height: 26),
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: const BorderSide(color: Color(0xFFE5EAF1))),
            child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(children: [
                  ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(usuario['nombre'] as String),
                      subtitle: const Text('Nombre completo')),
                  ListTile(
                      leading: const Icon(Icons.mail_outline),
                      title: Text(usuario['correo'] as String),
                      subtitle: const Text('Correo electrónico')),
                  ListTile(
                      leading: const Icon(Icons.badge_outlined),
                      title: Text(rol),
                      subtitle: const Text('Tipo de usuario')),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                      onPressed: sesion.cerrar,
                      icon: const Icon(Icons.logout),
                      label: const Text('Cerrar sesión')),
                ])),
          ),
        ]),
      )),
    );
  }
}
