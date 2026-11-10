import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/credito_theme.dart';
import '../../../services/api_exception.dart';
import '../providers/sesion_provider.dart';
import 'auth_widgets.dart';
import 'registro_usuario_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _correo = TextEditingController();
  final _password = TextEditingController();
  bool _mostrar = false;
  bool _registro = false;
  String? _error;

  @override
  void dispose() {
    _correo.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _ingresar() async {
    final sesion = context.read<SesionProvider>();
    if (sesion.ocupado || !_form.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      await sesion.ingresar(_correo.text, _password.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo iniciar sesión. Intenta nuevamente.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sesion = context.watch<SesionProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final expanded = constraints.maxWidth >= 1040;
            final content = _registro
                ? Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => setState(() => _registro = false),
                            icon:
                                const Icon(Icons.arrow_back_rounded, size: 18),
                            label: const Text('Volver a iniciar sesión'),
                          ),
                        ),
                      ),
                      Expanded(
                        child: RegistroUsuarioScreen(
                          esperaAutenticacion: sesion.esperaAutenticacion,
                          onGuardar: sesion.registrar,
                          onCreado: (correo) => setState(() {
                            _correo.text = correo;
                            _password.clear();
                            _error = null;
                            _registro = false;
                          }),
                        ),
                      ),
                    ],
                  )
                : _login(sesion, expanded);

            if (!expanded) return content;
            return Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: AuthEditorialPanel(registro: _registro),
                  ),
                ),
                Expanded(flex: 6, child: content),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _login(SesionProvider sesion, bool expanded) {
    final text = Theme.of(context).textTheme;
    final compact = MediaQuery.sizeOf(context).height < 700;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: expanded ? 48 : 24,
          vertical: 20,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!expanded) ...[
                  const AuthBrand(),
                  SizedBox(height: compact ? 18 : 26),
                ],
                Text(
                  'QUÉ BUENO TENERTE AQUÍ',
                  style: text.labelSmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Tu próximo paso\nempieza aquí.',
                  style: text.headlineLarge?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                    height: 1.12,
                    letterSpacing: -1.2,
                    fontSize: expanded ? 40 : (compact ? 28 : 32),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Ingresa a tu cuenta y sigamos creciendo juntos.',
                  style: TextStyle(color: AppColors.muted, height: 1.5),
                ),
                SizedBox(height: compact ? 20 : 26),
                Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _correo,
                        enabled: !sesion.ocupado,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        decoration: authInputDecoration(
                          'Correo electrónico',
                          Icons.mail_outline_rounded,
                          hint: 'nombre@correo.com',
                        ),
                        validator: (v) => (v?.trim().isEmpty ?? true)
                            ? 'Escribe tu correo electrónico'
                            : null,
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _password,
                        enabled: !sesion.ocupado,
                        obscureText: !_mostrar,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _ingresar(),
                        decoration: authInputDecoration(
                          'Contraseña',
                          Icons.lock_outline_rounded,
                          suffixIcon: IconButton(
                            tooltip: _mostrar
                                ? 'Ocultar contraseña'
                                : 'Mostrar contraseña',
                            onPressed: () =>
                                setState(() => _mostrar = !_mostrar),
                            icon: Icon(
                              _mostrar
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                            ),
                          ),
                        ),
                        validator: (v) => (v?.isEmpty ?? true)
                            ? 'Escribe tu contraseña'
                            : null,
                      ),
                      if (_error != null || sesion.mensaje != null) ...[
                        const SizedBox(height: 16),
                        Semantics(
                          liveRegion: true,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0ED),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.info_outline_rounded,
                                  color: AppColors.error,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _error ?? sesion.mensaje!,
                                    style: const TextStyle(
                                      color: AppColors.error,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 52),
                        child: FilledButton(
                          onPressed: sesion.ocupado ? null : _ingresar,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  sesion.esperaAutenticacion > 0
                                      ? 'Reintentar en ${sesion.esperaAutenticacion} s'
                                      : sesion.ocupado
                                          ? 'Ingresando...'
                                          : 'Iniciar sesión',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Icon(Icons.arrow_forward_rounded, size: 19),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: sesion.ocupado
                            ? null
                            : () => setState(() {
                                  _password.clear();
                                  _error = null;
                                  _registro = true;
                                }),
                        child: const Text(
                          '¿No tienes cuenta? Crear una cuenta',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 14,
                      color: AppColors.muted,
                    ),
                    SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        'Un espacio para avanzar con confianza.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
