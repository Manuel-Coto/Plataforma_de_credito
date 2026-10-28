import 'package:flutter/material.dart';
import '../../../services/api_exception.dart';

class RegistroUsuarioScreen extends StatefulWidget {
  const RegistroUsuarioScreen({super.key, required this.onGuardar, this.onCreado});

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
        const SnackBar(content: Text('No se pudo completar el registro. Intenta nuevamente.')),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionEyebrow(
                icon: Icons.person_add_alt_1,
                label: 'USUARIOS',
              ),
              const SizedBox(height: 12),
              Text(
                'Crear una cuenta',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF172B4D),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Registra un nuevo perfil para acceder a la plataforma.',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: const Color(0xFF65758B)),
              ),
              const SizedBox(height: 26),
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                  side: const BorderSide(color: Color(0xFFE5EAF1)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Datos de la cuenta',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF172B4D),
                              ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Completa la información para registrar al usuario.',
                          style: TextStyle(color: Color(0xFF65758B)),
                        ),
                        const SizedBox(height: 24),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final twoColumns = constraints.maxWidth >= 620;
                            final nameField = _field(
                              controller: _nombre,
                              label: 'Nombre completo',
                              hint: 'Ej. María López',
                              icon: Icons.person_outline,
                              validator: (value) {
                                final name = value?.trim() ?? '';
                                if (name.isEmpty)
                                  return 'Escribe el nombre completo';
                                if (name.length > 250)
                                  return 'Máximo 250 caracteres';
                                return null;
                              },
                            );
                            final emailField = _field(
                              controller: _correo,
                              label: 'Correo electrónico',
                              hint: 'nombre@empresa.com',
                              icon: Icons.mail_outline,
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                final email = value?.trim() ?? '';
                                if (email.isEmpty)
                                  return 'Escribe el correo electrónico';
                                if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                    .hasMatch(email))
                                  return 'Escribe un correo válido';
                                return null;
                              },
                            );
                            if (!twoColumns) {
                              return Column(
                                children: [
                                  nameField,
                                  const SizedBox(height: 18),
                                  emailField,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: nameField),
                                const SizedBox(width: 18),
                                Expanded(child: emailField),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 18),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final twoColumns = constraints.maxWidth >= 620;
                            final roleField = DropdownButtonFormField<String>(
                              initialValue: _rol,
                              decoration: _decoration(
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
                              onChanged: (value) =>
                                  setState(() => _rol = value ?? 'pyme'),
                            );
                            final passwordField = _field(
                              controller: _password,
                              label: 'Contraseña',
                              hint: 'Crea una contraseña segura',
                              icon: Icons.lock_outline,
                              obscureText: !_mostrarPassword,
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
                                ),
                              ),
                              validator: (value) {
                                final password = value ?? '';
                                if (password.length < 12)
                                  return 'Usa al menos 12 caracteres';
                                final categories = [
                                  RegExp(r'[a-z]').hasMatch(password),
                                  RegExp(r'[A-Z]').hasMatch(password),
                                  RegExp(r'[0-9]').hasMatch(password),
                                  RegExp(r'[^A-Za-z0-9\s]').hasMatch(password),
                                ].where((item) => item).length;
                                if (categories < 3)
                                  return 'Combina 3 tipos: mayúsculas, minúsculas, números o símbolos';
                                return null;
                              },
                            );
                            if (!twoColumns)
                              return Column(
                                children: [
                                  roleField,
                                  const SizedBox(height: 18),
                                  passwordField,
                                ],
                              );
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: roleField),
                                const SizedBox(width: 18),
                                Expanded(child: passwordField),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: FilledButton.icon(
                            onPressed: _guardando ? null : _guardar,
                            icon: const Icon(Icons.person_add_alt_1),
                            label: Text(
                              _guardando ? 'Creando cuenta...' : 'Crear cuenta',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF176B68),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 18,
                              color: Color(0xFF65758B),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'La contraseña debe tener 12 caracteres o más y combinar al menos tres tipos de caracteres.',
                                style: TextStyle(
                                  color: Color(0xFF65758B),
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionEyebrow extends StatelessWidget {
  const _SectionEyebrow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFE7F3F1),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF176B68)),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF176B68),
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      ],
    ),
  );
}

Widget _field({
  required TextEditingController controller,
  required String label,
  required String hint,
  required IconData icon,
  required String? Function(String?) validator,
  TextInputType? keyboardType,
  bool obscureText = false,
  Widget? suffixIcon,
}) => TextFormField(
  controller: controller,
  keyboardType: keyboardType,
  obscureText: obscureText,
  validator: validator,
  decoration: _decoration(label, icon, hint: hint, suffixIcon: suffixIcon),
);

InputDecoration _decoration(
  String label,
  IconData icon, {
  String? hint,
  Widget? suffixIcon,
}) => InputDecoration(
  labelText: label,
  hintText: hint,
  prefixIcon: Icon(icon, size: 20),
  suffixIcon: suffixIcon,
  filled: true,
  fillColor: const Color(0xFFFAFBFD),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(13),
    borderSide: const BorderSide(color: Color(0xFFDCE3EC)),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(13),
    borderSide: const BorderSide(color: Color(0xFFDCE3EC)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(13),
    borderSide: const BorderSide(color: Color(0xFF176B68), width: 1.6),
  ),
  errorMaxLines: 2,
);
