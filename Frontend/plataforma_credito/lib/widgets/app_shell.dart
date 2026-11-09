import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/credito_theme.dart';
import '../modules/administracion/screens/administracion_hub_screen.dart';
import '../modules/creditos/screens/operaciones_screen.dart';
import '../modules/empresas/screens/empresa_revision_screen.dart';
import '../modules/facturas/screens/facturas_lista_screen.dart';
import '../modules/usuarios/providers/sesion_provider.dart';
import '../modules/usuarios/screens/cuenta_screen.dart';
import '../modules/inversiones/screens/inversiones_screen.dart';
import 'offline_status.dart';
import 'session_actions.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selected = 0;
  final _visited = <int>{0};

  static const _items = [
    (
      label: 'Mi espacio',
      short: 'Inicio',
      icon: Icons.space_dashboard_outlined,
      active: Icons.space_dashboard_rounded,
      caption: 'Tu cuenta, en un solo lugar'
    ),
    (
      label: 'Empresas',
      short: 'Empresas',
      icon: Icons.business_outlined,
      active: Icons.business_rounded,
      caption: 'El siguiente paso para tu empresa'
    ),
    (
      label: 'Facturas',
      short: 'Facturas',
      icon: Icons.receipt_long_outlined,
      active: Icons.receipt_long_rounded,
      caption: 'Cada factura, con más claridad'
    ),
    (
      label: 'Créditos y pagos',
      short: 'Créditos',
      icon: Icons.account_balance_wallet_outlined,
      active: Icons.account_balance_wallet_rounded,
      caption: 'Acompaña el avance de tus operaciones'
    ),
    (
      label: 'Administración',
      short: 'Panel',
      icon: Icons.donut_large_outlined,
      active: Icons.donut_large_rounded,
      caption: 'Una mirada al movimiento de la plataforma'
    ),
    (
      label: 'Ofertas e inversiones',
      short: 'Invertir',
      icon: Icons.trending_up_outlined,
      active: Icons.trending_up_rounded,
      caption: 'Conecta oportunidades y financiamiento'
    ),
  ];

  List<int> get _visibles =>
      switch (context.read<SesionProvider>().usuario?['rol']) {
        'administrador' => [0, 1, 2, 3, 4, 5],
        'pyme' => [0, 1, 2, 3, 5],
        'inversionista' => [0, 2, 3, 5],
        _ => [0],
      };

  int get _actual => _visibles.contains(_selected) ? _selected : 0;

  void _navigate(int index) {
    if (!_visibles.contains(index)) return;
    setState(() {
      _selected = index;
      _visited.add(index);
    });
  }

  Widget _page(int index) => switch (index) {
        0 => CuentaScreen(onNavigate: _navigate),
        1 => const EmpresaRevisionScreen(),
        2 => const FacturasListaScreen(),
        3 => const OperacionesScreen(),
        4 => const AdministracionHubScreen(),
        _ => const InversionesScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final sesion = context.watch<SesionProvider>();
    final visibles = _visibles;
    final rol = switch (sesion.usuario?['rol']) {
      'pyme' => 'Cuenta PYME',
      'inversionista' => 'Inversionista',
      'administrador' => 'Administración',
      _ => 'Mi cuenta',
    };
    return LayoutBuilder(builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 1000;
      return Scaffold(
        body: SafeArea(
          child: Row(children: [
            if (desktop) _sidebar(sesion),
            Expanded(
              child: Column(children: [
                Container(
                  height: desktop ? 86 : 72,
                  padding: EdgeInsets.symmetric(horizontal: desktop ? 36 : 20),
                  decoration: const BoxDecoration(
                    color: AppColors.background,
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(children: [
                    if (!desktop) ...[
                      const BrandMark(compact: true),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              desktop
                                  ? 'TU ESPACIO FINANCIERO'
                                  : 'CRÉDITO COLABORATIVO',
                              style: const TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 1.6,
                                  color: AppColors.muted,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 5),
                          Text(
                              desktop
                                  ? _items[_actual].caption
                                  : _items[_actual].label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: desktop ? 14 : 13,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (desktop) ...[
                      Container(width: 1, height: 28, color: AppColors.border),
                      const SizedBox(width: 20),
                      Text(rol,
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 13)),
                      const SizedBox(width: 14),
                    ],
                    IconButton(
                      tooltip: 'Ver mi cuenta',
                      onPressed: () => _navigate(0),
                      icon: const CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.softPrimary,
                        child: Icon(Icons.person_outline_rounded,
                            color: AppColors.primary, size: 20),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Sincronización',
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) =>
                                  SincronizacionScreen(api: sesion.api))),
                      icon: const Icon(Icons.cloud_sync_outlined, size: 20),
                    ),
                    if (!desktop)
                      IconButton(
                        tooltip: 'Cerrar sesión',
                        onPressed: () => confirmarCierreSesion(context, sesion),
                        icon: const Icon(Icons.logout_rounded, size: 20),
                      ),
                  ]),
                ),
                OfflineStatus(api: sesion.api),
                Expanded(
                  child: IndexedStack(
                    index: _actual,
                    children: List.generate(
                        _items.length,
                        (i) => _visited.contains(i)
                            ? _page(i)
                            : const SizedBox.shrink()),
                  ),
                ),
              ]),
            ),
          ]),
        ),
        bottomNavigationBar: desktop
            ? null
            : DecoratedBox(
                decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.border))),
                child: NavigationBar(
                  selectedIndex:
                      visibles.indexOf(_actual).clamp(0, visibles.length - 1),
                  onDestinationSelected: (index) => _navigate(visibles[index]),
                  height: 72,
                  destinations: [
                    for (final item in visibles.map((index) => _items[index]))
                      NavigationDestination(
                        icon: Icon(item.icon, size: 22),
                        selectedIcon: Icon(item.active, size: 22),
                        label: item.short,
                      )
                  ],
                ),
              ),
      );
    });
  }

  Widget _sidebar(SesionProvider sesion) => Container(
        width: 244,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(right: BorderSide(color: AppColors.border)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                          padding: EdgeInsets.fromLTRB(28, 32, 20, 44),
                          child: BrandMark()),
                      const Padding(
                        padding: EdgeInsets.only(left: 28, bottom: 16),
                        child: Text('PRINCIPAL',
                            style: TextStyle(
                                fontSize: 10,
                                letterSpacing: 1.7,
                                color: AppColors.muted,
                                fontWeight: FontWeight.w600)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(children: [
                          for (final i in _visibles)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 7),
                              child: Material(
                                color: _actual == i
                                    ? AppColors.softPrimary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _navigate(i),
                                  child: Semantics(
                                    selected: _actual == i,
                                    button: true,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 15, vertical: 16),
                                      child: Row(children: [
                                        Icon(
                                            _actual == i
                                                ? _items[i].active
                                                : _items[i].icon,
                                            size: 21,
                                            color: _actual == i
                                                ? AppColors.primary
                                                : AppColors.muted),
                                        const SizedBox(width: 12),
                                        Expanded(
                                            child: Text(_items[i].label,
                                                style: TextStyle(
                                                  color: _actual == i
                                                      ? AppColors.primary
                                                      : AppColors.muted,
                                                  fontSize: 13,
                                                  fontWeight: _actual == i
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                                ))),
                                        if (_actual == i)
                                          Container(
                                              width: 5,
                                              height: 5,
                                              decoration: const BoxDecoration(
                                                  color: AppColors.primary,
                                                  shape: BoxShape.circle)),
                                      ]),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ]),
                      ),
                      const Spacer(),
                      Container(
                        margin: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(16)),
                        child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.eco_outlined,
                                  size: 24, color: AppColors.primary),
                              SizedBox(height: 12),
                              Text('Crecer, juntos.',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700)),
                              SizedBox(height: 6),
                              Text(
                                  'Conecta tu empresa con nuevas posibilidades.',
                                  style: TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 12,
                                      height: 1.6)),
                            ]),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Tooltip(
                          message: 'Cerrar sesión',
                          child: TextButton.icon(
                            onPressed: () =>
                                confirmarCierreSesion(context, sesion),
                            style: TextButton.styleFrom(
                                foregroundColor: AppColors.muted,
                                alignment: Alignment.centerLeft),
                            icon: const Icon(Icons.logout_rounded, size: 19),
                            label: const Text('Cerrar sesión'),
                          ),
                        ),
                      ),
                    ]),
              ),
            ),
          ),
        ),
      );
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(13)),
          child:
              const Icon(Icons.spa_outlined, color: AppColors.accent, size: 24),
        ),
        if (!compact) ...[
          const SizedBox(width: 12),
          const Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Crédito',
                        style: TextStyle(
                            fontSize: 23,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.6)),
                    SizedBox(height: 3),
                    Text('C O L A B O R A T I V O',
                        style: TextStyle(
                            fontSize: 7,
                            color: AppColors.muted,
                            fontWeight: FontWeight.w600)),
                  ]),
            ),
          ),
        ],
      ]);
}
