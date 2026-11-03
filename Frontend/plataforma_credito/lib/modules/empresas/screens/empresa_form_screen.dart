import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EmpresaFormScreen extends StatefulWidget {
  const EmpresaFormScreen({super.key, this.onGuardar});

  final Future<void> Function(Map<String, String>)? onGuardar;

  @override
  State<EmpresaFormScreen> createState() => _EmpresaFormScreenState();
}

class _EmpresaFormScreenState extends State<EmpresaFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _nit = TextEditingController();
  final _correo = TextEditingController();
  final _telefono = TextEditingController();
  final _direccion = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _nit.dispose();
    _correo.dispose();
    _telefono.dispose();
    _direccion.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _enviando = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onGuardar?.call({
        'nombre': _nombre.text.trim(),
        'nit': _nit.text.trim(),
        'correo': _correo.text.trim(),
        'telefono': _telefono.text.trim(),
        'direccion': _direccion.text.trim(),
      });
      if (!mounted) return;
      for (final c in [_nombre, _nit, _correo, _telefono, _direccion]) {
        c.clear();
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Empresa registrada. Estado: Pendiente.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo registrar la empresa: $e')),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F3F1),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.business_outlined,
                      size: 16,
                      color: Color(0xFF176B68),
                    ),
                    SizedBox(width: 7),
                    Text(
                      'EMPRESAS',
                      style: TextStyle(
                        color: Color(0xFF176B68),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Registrar empresa',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF172B4D),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Agrega los datos de la empresa para iniciar su registro en la plataforma.',
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
                          'Información de la empresa',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF172B4D),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Los campos marcados son necesarios para registrar la empresa.',
                          style: TextStyle(color: Color(0xFF65758B)),
                        ),
                        const SizedBox(height: 24),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final twoColumns = constraints.maxWidth >= 620;
                            final name = _companyField(
                              _nombre,
                              'Nombre de la empresa',
                              'Ej. Soluciones del Valle',
                              Icons.business_outlined,
                              required: true,
                              maxLength: 250,
                            );
                            final nit = _companyField(
                              _nit,
                              'NIT',
                              'Ej. 123456789',
                              Icons.badge_outlined,
                              required: true,
                              maxLength: 9,
                              minLength: 9,
                              digitsOnly: true,
                              keyboardType: TextInputType.number,
                            );
                            if (!twoColumns) {
                              return Column(
                                children: [
                                  name,
                                  const SizedBox(height: 18),
                                  nit,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: name),
                                const SizedBox(width: 18),
                                Expanded(child: nit),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 18),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final twoColumns = constraints.maxWidth >= 620;
                            final email = _companyField(
                              _correo,
                              'Correo electrónico',
                              'contacto@empresa.com',
                              Icons.mail_outline,
                              required: true,
                              keyboardType: TextInputType.emailAddress,
                              maxLength: 254,
                            );
                            final phone = _companyField(
                              _telefono,
                              'Teléfono',
                              'Ej. 22223344',
                              Icons.phone_outlined,
                              maxLength: 8,
                              digitsOnly: true,
                              keyboardType: TextInputType.phone,
                            );
                            if (!twoColumns) {
                              return Column(
                                children: [
                                  email,
                                  const SizedBox(height: 18),
                                  phone,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: email),
                                const SizedBox(width: 18),
                                Expanded(child: phone),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _direccion,
                          maxLength: 1000,
                          maxLines: 3,
                          decoration: _companyDecoration(
                            'Dirección',
                            Icons.location_on_outlined,
                            hint: 'Dirección de la empresa',
                          ),
                        ),
                        const SizedBox(height: 22),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2F7FA),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Color(0xFF54718C),
                                size: 19,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Al registrar la empresa, su estado inicial será “Pendiente” hasta que se complete la revisión.',
                                  style: TextStyle(
                                    color: Color(0xFF54718C),
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: FilledButton.icon(
                            onPressed: _enviando ? null : _guardar,
                            icon: _enviando
                                ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                                : const Icon(Icons.save_outlined),
                            label: const Text(
                              'Guardar empresa',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF176B68),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13),
                              ),
                            ),
                          ),
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

Widget _companyField(
    TextEditingController controller,
    String label,
    String hint,
    IconData icon, {
      bool required = false,
      int? maxLength,
      int? minLength,
      bool digitsOnly = false,
      TextInputType? keyboardType,
    }) => TextFormField(
  controller: controller,
  keyboardType: keyboardType,
  maxLength: maxLength,
  inputFormatters: [
    if (digitsOnly) FilteringTextInputFormatter.digitsOnly,
  ],
  validator: (value) {
    final text = value?.trim() ?? '';
    if (required && text.isEmpty) return 'Completa este campo';
    if (minLength != null && text.isNotEmpty && text.length < minLength) {
      return '$label debe tener $minLength dígitos';
    }
    if (label == 'Correo electrónico' &&
        text.isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
      return 'Escribe un correo válido';
    }
    return null;
  },
  decoration: _companyDecoration(label, icon, hint: hint),
);

InputDecoration _companyDecoration(
    String label,
    IconData icon, {
      String? hint,
    }) => InputDecoration(
  labelText: label,
  hintText: hint,
  prefixIcon: Icon(icon, size: 20),
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