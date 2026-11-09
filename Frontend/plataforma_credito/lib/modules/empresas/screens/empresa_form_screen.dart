import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/credito_theme.dart';
import '../../../widgets/page_header.dart';
import '../../../services/api_client.dart';

class EmpresaFormScreen extends StatefulWidget {
  const EmpresaFormScreen(
      {super.key, this.onGuardar, this.initialData, this.onGuardado});
  final Map<String, dynamic>? initialData;
  final VoidCallback? onGuardado;

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
  bool get _editando => widget.initialData != null;

  @override
  void initState() {
    super.initState();
    final data = widget.initialData;
    if (data != null) {
      _nombre.text = data['nombre'] as String? ?? '';
      _nit.text = data['nit'] as String? ?? '';
      _correo.text = data['correo'] as String? ?? '';
      _telefono.text = data['telefono'] as String? ?? '';
      _direccion.text = data['direccion'] as String? ?? '';
    }
  }

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
    if (_enviando || !_formKey.currentState!.validate()) return;
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
      if (widget.onGuardado != null) {
        messenger.showSnackBar(SnackBar(
            content: Text(_editando
                ? 'Empresa actualizada.'
                : 'Empresa registrada. Estado: Pendiente.')));
        widget.onGuardado!();
        return;
      }
      for (final c in [_nombre, _nit, _correo, _telefono, _direccion]) {
        c.clear();
      }
      messenger.showSnackBar(const SnackBar(
          content: Text('Empresa registrada. Estado: Pendiente.')));
    } on OfflineQueuedException {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
          content: Text(
              'Cambio guardado en este equipo. Abre Sincronización para enviarlo cuando vuelva la conexión.')));
      if (widget.onGuardado != null) {
        widget.onGuardado!();
      } else {
        for (final c in [_nombre, _nit, _correo, _telefono, _direccion]) {
          c.clear();
        }
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text('No se pudo registrar la empresa: $e')));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, viewport) => SingleChildScrollView(
          padding: EdgeInsets.all(viewport.maxWidth < 600 ? 20 : 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1160),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PageHeader(
                    eyebrow: 'EL PRIMER PASO PARA CRECER',
                    title: _editando ? 'Editar empresa' : 'Registrar empresa',
                    subtitle: _editando
                        ? 'Los cambios en empresas activas o rechazadas requieren una nueva revisión.'
                        : 'Cuéntanos sobre tu empresa. Te acompañamos desde aquí.',
                  ),
                  const SizedBox(height: 28),
                  LayoutBuilder(builder: (context, constraints) {
                    final form = _buildForm(context);
                    if (constraints.maxWidth < 960) {
                      return Column(children: [
                        form,
                        const SizedBox(height: 22),
                        if (!_editando) const _RegistrationGuide(),
                      ]);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: form),
                        const SizedBox(width: 24),
                        if (!_editando)
                          const SizedBox(
                              width: 270, child: _RegistrationGuide()),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _buildForm(BuildContext context) => Container(
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(22)),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _FormSection(
                number: '01',
                title: 'Identidad de la empresa',
                description: 'Usa los datos oficiales de tu empresa.',
              ),
              const SizedBox(height: 24),
              _fieldPair(
                _companyField(_nombre, 'Nombre de la empresa',
                    'Ej. Soluciones del Valle', Icons.business_outlined,
                    isRequired: true, maxLength: 250),
                _companyField(
                    _nit, 'NIT', 'Ej. 123456789', Icons.badge_outlined,
                    isRequired: true,
                    maxLength: 9,
                    minLength: 9,
                    digitsOnly: true,
                    keyboardType: TextInputType.number),
              ),
              const SizedBox(height: 25),
              const Divider(height: 1),
              const SizedBox(height: 27),
              const _FormSection(
                number: '02',
                title: 'Información de contacto',
                description: '¿Cómo podemos contactar a tu empresa?',
              ),
              const SizedBox(height: 24),
              _fieldPair(
                _companyField(_correo, 'Correo electrónico',
                    'contacto@empresa.com', Icons.mail_outline,
                    isRequired: true,
                    maxLength: 254,
                    keyboardType: TextInputType.emailAddress),
                _companyField(
                    _telefono, 'Teléfono', 'Ej. 22223344', Icons.phone_outlined,
                    maxLength: 8,
                    digitsOnly: true,
                    keyboardType: TextInputType.phone),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _direccion,
                enabled: !_enviando,
                maxLength: 1000,
                maxLines: 3,
                decoration: _companyDecoration(
                    'Dirección', Icons.location_on_outlined,
                    hint: 'Dirección de la empresa'),
              ),
              const SizedBox(height: 10),
              const Text('* Campos obligatorios',
                  style: TextStyle(color: AppColors.muted, fontSize: 12)),
              const SizedBox(height: 24),
              const Divider(height: 1),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _enviando ? null : _guardar,
                  icon: _enviando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.arrow_forward_rounded, size: 19),
                  label: Text(_enviando
                      ? 'Guardando empresa...'
                      : _editando
                          ? 'Guardar cambios'
                          : 'Guardar empresa'),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                    _editando
                        ? 'Una empresa inactiva permanecerá inactiva después de editarse.'
                        : 'Tu registro se enviará a revisión.',
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: AppColors.muted, fontSize: 12)),
              ),
            ],
          ),
        ),
      );

  Widget _fieldPair(Widget first, Widget second) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 560) {
            return Column(
                children: [first, const SizedBox(height: 18), second]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first),
              const SizedBox(width: 18),
              Expanded(child: second)
            ],
          );
        },
      );

  Widget _companyField(TextEditingController controller, String label,
          String hint, IconData icon,
          {bool isRequired = false,
          int? maxLength,
          int? minLength,
          bool digitsOnly = false,
          TextInputType? keyboardType}) =>
      TextFormField(
        controller: controller,
        enabled: !_enviando,
        keyboardType: keyboardType,
        maxLength: maxLength,
        textInputAction: TextInputAction.next,
        inputFormatters: [
          if (digitsOnly) FilteringTextInputFormatter.digitsOnly
        ],
        validator: (value) {
          final text = value?.trim() ?? '';
          if (isRequired && text.isEmpty) return 'Completa este campo';
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
        decoration: _companyDecoration(isRequired ? '$label *' : label, icon,
            hint: hint),
      );
}

InputDecoration _companyDecoration(String label, IconData icon,
        {String? hint}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 20),
      counterText: '',
      errorMaxLines: 2,
    );

class _FormSection extends StatelessWidget {
  const _FormSection(
      {required this.number, required this.title, required this.description});
  final String number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: AppColors.softPrimary,
                borderRadius: BorderRadius.circular(11)),
            child: Text(number,
                style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 5),
              Text(description,
                  style: const TextStyle(
                      color: AppColors.muted, fontSize: 12, height: 1.5)),
            ],
          )),
        ],
      );
}

class _RegistrationGuide extends StatelessWidget {
  const _RegistrationGuide();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
            color: AppColors.softPrimary,
            borderRadius: BorderRadius.circular(22)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.spa_outlined, size: 30, color: AppColors.primary),
            const SizedBox(height: 21),
            Text('Un paso más cerca',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            const Text(
                'Un registro completo nos ayuda a conocer mejor tu empresa.',
                style: TextStyle(color: AppColors.muted, height: 1.6)),
            const SizedBox(height: 25),
            _step('1', 'Completa tus datos',
                'Revisa el nombre, el NIT y el correo antes de guardar.'),
            const SizedBox(height: 20),
            _step('2', 'Envía el registro',
                'La empresa quedará en estado Pendiente para su revisión.'),
          ],
        ),
      );

  Widget _step(String number, String title, String description) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: AppColors.primary, shape: BoxShape.circle),
            child: Text(number,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              const SizedBox(height: 5),
              Text(description,
                  style: const TextStyle(
                      color: AppColors.muted, height: 1.5, fontSize: 12)),
            ],
          )),
        ],
      );
}
