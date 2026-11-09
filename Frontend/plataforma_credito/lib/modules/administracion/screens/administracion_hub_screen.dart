import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../usuarios/providers/sesion_provider.dart';
import '../../usuarios/screens/usuarios_gestion_screen.dart';
import 'dashboard_screen.dart';
import 'reportes_auditoria_screen.dart';

class AdministracionHubScreen extends StatelessWidget {
  const AdministracionHubScreen({super.key});
  @override
  Widget build(BuildContext context) {
    if (context.watch<SesionProvider>().usuario?['rol'] != 'administrador') {
      return const Center(
          child: Text('Se requiere una cuenta administradora.'));
    }
    return const DefaultTabController(
        length: 3,
        child: Column(children: [
          TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: 'Resumen'),
            Tab(text: 'Reportes y auditoría'),
            Tab(text: 'Usuarios'),
          ]),
          Expanded(
              child: TabBarView(children: [
            DashboardScreen(),
            ReportesAuditoriaScreen(),
            UsuariosGestionScreen()
          ])),
        ]));
  }
}
