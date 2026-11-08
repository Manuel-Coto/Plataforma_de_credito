import 'package:flutter/material.dart';

import '../../../core/theme/credito_theme.dart';
import '../../../services/api_exception.dart';
import 'auth_widgets.dart';

class RegistroUsuarioScreen extends StatefulWidget {
  const RegistroUsuarioScreen(
      {super.key, required this.onGuardar, this.onCreado});

  final Future<void> Function(Map<String, String>) onGuardar;
  final ValueChanged<String>? onCreado;

  @override
  State<RegistroUsuarioScreen> createState() => _RegistroUsuarioScreenState();
}

class _RegistroUsuarioScreenState extends State<RegistroUsuarioScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _correo = TextEditingController();
  final _password = TextEditingController();
  String _rol = 'pyme';
  bool _mostrarPassword = false;
  bool _guardando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _correo.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando || !_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      await widget.onGuardar({
        'nombre': _nombre.text.trim(),
        'correo': _correo.text.trim(),
        'password': _password.text,
        'rol': _rol,
      });
      if (!mounted) return;
      _password.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cuenta creada correctamente.')),
      );
      widget.onCreado?.call(_correo.text.trim());
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo completar el registro. Intenta nuevamente.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TU PRIMER PASO',
                style: text.labelSmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Crear una cuenta',
                style: text.headlineMedium?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.8,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Cuéntanos un poco de ti. Juntos, podemos llegar más lejos.',
                style: TextStyle(color: AppColors.muted, height: 1.6),
              ),
              const SizedBox(height: 26),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                padding: const EdgeInsets.all(24),
                child: AutofillGroup(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Tus datos',
                          style: TextStyle(
                            color: AppColors.ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Usaremos esta información para crear tu perfil.',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 26),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final nombre = TextFormField(
                              controller: _nombre,
                              enabled: !_guardando,
                              textCapitalization: TextCapitalization.words,
                              autofillHints: const [AutofillHints.name],
                              textInputAction: TextInputAction.next,
                              decoration: authInputDecoration(
                                'Nombre completo',
                                Icons.person_outline_rounded,
                                hint: 'Ej. María López',
                              ),
                              validator: (value) {
                                final name = value?.trim() ?? '';
                                if (name.isEmpty) {
                                  return 'Escribe el nombre completo';
                                }
                                if (name.length > 250) {
                                  return 'Máximo 250 caracteres';
                                }
                                return null;
                              },
                            );
                            final correo = TextFormField(
                              controller: _correo,
                              enabled: !_guardando,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              textInputAction: TextInputAction.next,
                              decoration: authInputDecoration(
                                'Correo electrónico',
                                Icons.mail_outline_rounded,
                                hint: 'nombre@correo.com',
                              ),
                              validator: (value) {
                                final email = value?.trim() ?? '';
                                if (email.isEmpty) {
                                  return 'Escribe el correo electrónico';
                                }
                                if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                    .hasMatch(email)) {
                                  return 'Escribe un correo válido';
                                }
                                return null;
                              },
                            );
                            if (constraints.maxWidth < 570) {
                              return Column(
                                children: [
                                  nombre,
                                  const SizedBox(height: 18),
                                  correo,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: nombre),
                                const SizedBox(width: 18),
                                Expanded(child: correo),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _password,
                          enabled: !_guardando,
                          obscureText: !_mostrarPassword,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _guardar(),
                          decoration: authInputDecoration(
                            'Contraseña',
                            Icons.lock_outline_rounded,
                            hint: 'Crea una contraseña segura',
                            suffixIcon: IconButton(
                              tooltip: _mostrarPassword
                                  ? 'Ocultar contraseña'
                                  : 'Mostrar contraseña',
                              onPressed: () => setState(
                                () => _mostrarPassword = !_mostrarPassword,
                              ),
                              icon: Icon(
                                _mostrarPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 20,
                              ),
                            ),
                          ),
                          validator: (value) {
                            final password = value ?? '';
                            if (password.length < 12) {
                              return 'Usa al menos 12 caracteres';
                            }
                            final categories = [
                              RegExp(r'[a-z]').hasMatch(password),
                              RegExp(r'[A-Z]').hasMatch(password),
                              RegExp(r'[0-9]').hasMatch(password),
                              RegExp(r'[^A-Za-z0-9\s]').hasMatch(password),
                            ].where((item) => item).length;
                            if (categories < 3) {
                              return 'Combina 3 tipos: mayúsculas, minúsculas, números o símbolos';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Usa 12 caracteres o más y combina al menos tres tipos: mayúsculas, minúsculas, números o símbolos.',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        DropdownButtonFormField<String>(
                          initialValue: _rol,
                          isExpanded: true,
                          decoration: authInputDecoration(
                            'Tipo de usuario',
                            Icons.badge_outlined,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'pyme',
                              child: Text('PYME'),
                            ),
                            DropdownMenuItem(
                              value: 'inversionista',
                              child: Text('Inversionista'),
                            ),
                          ],
                          onChanged: _guardando
                              ? null
                              : (value) =>
                                  setState(() => _rol = value ?? 'pyme'),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _rol == 'pyme'
                              ? 'Para empresas que buscan nuevas oportunidades de financiamiento.'
                              : 'Para personas que quieren impulsar el crecimiento de empresas.',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 28),
                        ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 52),
                          child: FilledButton(
                            onPressed: _guardando ? null : _guardar,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text(
                                    _guardando
                                        ? 'Creando cuenta...'
                                        : 'Crear cuenta',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Icon(Icons.arrow_forward_rounded,
                                    size: 19),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.spa_outlined,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'El primer paso de una historia que crece contigo.',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
