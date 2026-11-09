import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/credito_theme.dart';
import '../../../widgets/page_header.dart';
import '../../../widgets/session_actions.dart';
import '../../../services/api_exception.dart';
import '../providers/sesion_provider.dart';

class CuentaScreen extends StatelessWidget {
  const CuentaScreen({super.key, this.onNavigate});

  final ValueChanged<int>? onNavigate;

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
    return LayoutBuilder(builder: (context, viewport) {
      return SingleChildScrollView(
        padding: EdgeInsets.all(viewport.maxWidth < 600 ? 20 : 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1160),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PageHeader(
                  eyebrow: 'UN NUEVO DÍA, NUEVAS POSIBILIDADES',
                  title: 'Mi cuenta',
                  subtitle: 'Tu perfil y tus próximos pasos, en un solo lugar.',
                ),
                const SizedBox(height: 26),
                _WelcomeBanner(
                    onNavigate: onNavigate,
                    admin: usuario['rol'] == 'administrador',
                    inversionista: usuario['rol'] == 'inversionista'),
                const SizedBox(height: 30),
                LayoutBuilder(builder: (context, constraints) {
                  final profile = _ProfileCard(
                    nombre: usuario['nombre'] as String,
                    correo: usuario['correo'] as String,
                    rol: rol,
                    onLogout: () => confirmarCierreSesion(context, sesion),
                    onEdit: () => showDialog<bool>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => _EditarPerfilDialog(
                            nombre: usuario['nombre'] as String)),
                  );
                  final shortcuts = _NextSteps(
                      onNavigate: onNavigate, rol: usuario['rol'] as String);
                  if (constraints.maxWidth < 790) {
                    return Column(children: [
                      profile,
                      const SizedBox(height: 24),
                      shortcuts,
                    ]);
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: profile),
                      const SizedBox(width: 24),
                      Expanded(flex: 6, child: shortcuts),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner(
      {this.onNavigate, this.admin = false, this.inversionista = false});
  final bool admin;
  final bool inversionista;
  final ValueChanged<int>? onNavigate;

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(24),
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 850;
          return Padding(
            padding: EdgeInsets.all(constraints.maxWidth < 500 ? 24 : 34),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CRECEMOS CUANDO CONECTAMOS',
                        style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.6)),
                    const SizedBox(height: 15),
                    Text(
                        admin
                            ? 'Cada empresa merece\nuna revisión clara.'
                            : inversionista
                                ? 'Conecta tus metas\ncon nuevas oportunidades.'
                                : 'Dale espacio al futuro\nde tu empresa.',
                        style: TextStyle(
                            color: AppColors.onPrimary,
                            fontSize: wide ? 34 : 28,
                            height: 1.18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -.8)),
                    const SizedBox(height: 15),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Text(
                        admin
                            ? 'Consulta las empresas registradas y aprueba o rechaza las solicitudes pendientes.'
                            : inversionista
                                ? 'Explora las ofertas disponibles y consulta el avance de tus aportes y créditos.'
                                : 'Registra tu empresa, organiza tus facturas y sigue cada paso de tus operaciones con claridad.',
                        style: const TextStyle(
                            color: AppColors.onPrimaryMuted,
                            height: 1.6,
                            fontSize: 14),
                      ),
                    ),
                    if (onNavigate != null) ...[
                      const SizedBox(height: 26),
                      FilledButton.icon(
                        onPressed: () => onNavigate!(inversionista ? 5 : 1),
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: AppColors.primary),
                        icon: Icon(
                            inversionista
                                ? Icons.trending_up_rounded
                                : Icons.add_business_outlined,
                            size: 19),
                        label: Text(admin
                            ? 'Revisar empresas'
                            : inversionista
                                ? 'Explorar inversiones'
                                : 'Registrar mi empresa'),
                      ),
                    ],
                  ],
                ),
              ),
              if (wide) ...[
                const SizedBox(width: 30),
                const _ConnectionArtwork(),
              ],
            ]),
          );
        }),
      );
}

class _ConnectionArtwork extends StatelessWidget {
  const _ConnectionArtwork();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
          width: 240,
          height: 220,
          child: Stack(alignment: Alignment.center, children: [
            for (final diameter in [210.0, 148.0])
              Container(
                width: diameter,
                height: diameter,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primaryOutline)),
              ),
            Transform.rotate(
              angle: -.12,
              child: Container(
                width: 155,
                height: 106,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(19)),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.spa_outlined,
                        color: AppColors.primary, size: 29),
                    Spacer(),
                    Row(children: [
                      Expanded(child: Divider(color: AppColors.primary)),
                      SizedBox(width: 35),
                      Icon(Icons.north_east_rounded,
                          size: 20, color: AppColors.primary),
                    ]),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 9,
              right: 21,
              child: _artIcon(Icons.business_outlined, AppColors.primaryRaised,
                  AppColors.onPrimary),
            ),
            Positioned(
              bottom: 8,
              left: 5,
              child: _artIcon(Icons.receipt_long_outlined,
                  AppColors.softPrimary, AppColors.primary),
            ),
          ]),
        ),
      );

  Widget _artIcon(IconData icon, Color background, Color foreground) =>
      Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: background, borderRadius: BorderRadius.circular(15)),
        child: Icon(icon, color: foreground, size: 24),
      );
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard(
      {required this.nombre,
      required this.correo,
      required this.rol,
      required this.onEdit,
      required this.onLogout});
  final String nombre;
  final String correo;
  final String rol;
  final VoidCallback onLogout;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final initial = nombre.trim().isEmpty
        ? 'C'
        : nombre.trim().characters.first.toUpperCase();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Tu perfil', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 23),
        Row(children: [
          CircleAvatar(
            radius: 27,
            backgroundColor: AppColors.softPrimary,
            foregroundColor: AppColors.primary,
            child: Text(initial,
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 15),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(nombre, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(rol, style: const TextStyle(color: AppColors.muted)),
            ],
          )),
        ]),
        const SizedBox(height: 25),
        const Divider(height: 1),
        const SizedBox(height: 22),
        const Text('CORREO ELECTRÓNICO',
            style: TextStyle(
                color: AppColors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
        const SizedBox(height: 8),
        Text(correo, style: const TextStyle(color: AppColors.ink)),
        const SizedBox(height: 22),
        const Row(children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 17, color: AppColors.primary),
          SizedBox(width: 7),
          Text('Cuenta activa',
              style: TextStyle(color: AppColors.primary, fontSize: 13)),
        ]),
        const SizedBox(height: 20),
        OutlinedButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Editar perfil')),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: onLogout,
          icon: const Icon(Icons.logout_rounded, size: 17),
          label: const Text('Cerrar sesión'),
        ),
      ]),
    );
  }
}

class _EditarPerfilDialog extends StatefulWidget {
  const _EditarPerfilDialog({required this.nombre});
  final String nombre;

  @override
  State<_EditarPerfilDialog> createState() => _EditarPerfilDialogState();
}

class _EditarPerfilDialogState extends State<_EditarPerfilDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _nombre =
      TextEditingController(text: widget.nombre);
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando || !_form.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final messenger = ScaffoldMessenger.of(context);
      await context.read<SesionProvider>().actualizarPerfil(_nombre.text);
      if (!mounted) return;
      Navigator.pop(context, true);
      messenger
          .showSnackBar(const SnackBar(content: Text('Perfil actualizado.')));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'No se pudo actualizar el perfil. Intenta nuevamente.');
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_guardando,
      child: AlertDialog(
        scrollable: true,
        title: const Text('Editar perfil'),
        content: SizedBox(
            width: 420,
            child: Form(
                key: _form,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Actualiza el nombre que aparece en tu cuenta.'),
                  const SizedBox(height: 20),
                  TextFormField(
                      controller: _nombre,
                      enabled: !_guardando,
                      maxLength: 250,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                          labelText: 'Nombre completo',
                          prefixIcon: Icon(Icons.person_outline)),
                      validator: (value) => (value?.trim().isEmpty ?? true)
                          ? 'Escribe tu nombre'
                          : null,
                      onFieldSubmitted: (_) => _guardar()),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error!,
                            style: const TextStyle(color: AppColors.error))),
                ]))),
        actions: [
          TextButton(
              onPressed: _guardando ? null : () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: Text(_guardando ? 'Guardando...' : 'Guardar nombre')),
        ],
      ));
}

class _NextSteps extends StatelessWidget {
  const _NextSteps({this.onNavigate, required this.rol});
  final ValueChanged<int>? onNavigate;
  final String rol;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Todo a tu alcance',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text('Elige por dónde quieres continuar.',
              style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 21),
          if (rol != 'inversionista') ...[
            _shortcut(Icons.business_outlined, 'Gestión de empresas',
                'Accede a las opciones disponibles para tu cuenta.', 1),
            const SizedBox(height: 12),
            _shortcut(Icons.receipt_long_outlined, 'Organiza tus facturas',
                'Consulta documentos, montos y vencimientos.', 2),
            const SizedBox(height: 12),
          ],
          _shortcut(
              Icons.trending_up_rounded,
              rol == 'inversionista'
                  ? 'Explora tus inversiones'
                  : 'Ofertas e inversiones',
              'Consulta las ofertas y el avance de los aportes.',
              5),
          const SizedBox(height: 12),
          _shortcut(
              Icons.account_balance_wallet_outlined,
              'Sigue tus operaciones',
              'Revisa el estado de tus créditos y pagos.',
              3),
          if (rol == 'administrador') ...[
            const SizedBox(height: 12),
            _shortcut(Icons.admin_panel_settings_outlined, 'Administración',
                'Consulta indicadores, usuarios, reportes y auditoría.', 4),
          ],
        ],
      );

  Widget _shortcut(
          IconData icon, String title, String description, int index) =>
      Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onNavigate == null ? null : () => onNavigate!(index),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                    color: AppColors.softPrimary,
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 21, color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: AppColors.ink, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 5),
                  Text(description,
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 12, height: 1.45)),
                ],
              )),
              if (onNavigate != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded,
                    color: AppColors.primary, size: 18),
              ],
            ]),
          ),
        ),
      );
}
