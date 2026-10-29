import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../services/api_exception.dart';
import '../providers/sesion_provider.dart';
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
            () => _error = 'No se pudo iniciar sesión. Intenta nuevamente.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sesion = context.watch<SesionProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Plataforma de Crédito')),
      body: _registro
          ? Column(children: [
              Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _registro = false),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Volver a iniciar sesión'),
                  )),
              Expanded(
                  child: RegistroUsuarioScreen(
                onGuardar: sesion.registrar,
                onCreado: (correo) => setState(() {
                  _correo.text = correo;
                  _password.clear();
                  _error = null;
                  _registro = false;
                }),
              )),
            ])
          : Center(
              child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.account_balance_rounded,
                          size: 40, color: Color(0xFF176B68)),
                      const SizedBox(height: 16),
                      Text('Iniciar sesión',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF172B4D))),
                      const SizedBox(height: 8),
                      const Text('Accede con tu cuenta a la plataforma.',
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
                            child: Form(
                              key: _form,
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    TextFormField(
                                        controller: _correo,
                                        enabled: !sesion.ocupado,
                                        keyboardType:
                                            TextInputType.emailAddress,
                                        autofillHints: const [
                                          AutofillHints.username
                                        ],
                                        textInputAction: TextInputAction.next,
                                        decoration: _decoracion(
                                            'Correo electrónico',
                                            Icons.mail_outline),
                                        validator: (v) => (v?.trim().isEmpty ??
                                                true)
                                            ? 'Escribe tu correo electrónico'
                                            : null),
                                    const SizedBox(height: 18),
                                    TextFormField(
                                        controller: _password,
                                        enabled: !sesion.ocupado,
                                        obscureText: !_mostrar,
                                        autocorrect: false,
                                        enableSuggestions: false,
                                        autofillHints: const [
                                          AutofillHints.password
                                        ],
                                        onFieldSubmitted: (_) => _ingresar(),
                                        decoration: _decoracion('Contraseña',
                                                Icons.lock_outline)
                                            .copyWith(
                                                suffixIcon: IconButton(
                                                    tooltip: _mostrar
                                                        ? 'Ocultar contraseña'
                                                        : 'Mostrar contraseña',
                                                    onPressed: () => setState(
                                                        () =>
                                                            _mostrar =
                                                                !_mostrar),
                                                    icon: Icon(_mostrar
                                                        ? Icons
                                                            .visibility_off_outlined
                                                        : Icons
                                                            .visibility_outlined))),
                                        validator: (v) => (v?.isEmpty ?? true)
                                            ? 'Escribe tu contraseña'
                                            : null),
                                    if (_error != null ||
                                        sesion.mensaje != null) ...[
                                      const SizedBox(height: 16),
                                      Semantics(
                                          liveRegion: true,
                                          child: Text(_error ?? sesion.mensaje!,
                                              style: TextStyle(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .error))),
                                    ],
                                    const SizedBox(height: 28),
                                    SizedBox(
                                        height: 54,
                                        child: FilledButton.icon(
                                            onPressed: sesion.ocupado
                                                ? null
                                                : _ingresar,
                                            icon: const Icon(Icons.login),
                                            label: Text(sesion.ocupado
                                                ? 'Ingresando...'
                                                : 'Iniciar sesión'),
                                            style: FilledButton.styleFrom(
                                                backgroundColor:
                                                    const Color(0xFF176B68),
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            13))))),
                                    const SizedBox(height: 12),
                                    TextButton(
                                        onPressed: sesion.ocupado
                                            ? null
                                            : () => setState(() {
                                                  _password.clear();
                                                  _error = null;
                                                  _registro = true;
                                                }),
                                        child: const Text(
                                            '¿No tienes cuenta? Crear una cuenta')),
                                  ]),
                            )),
                      ),
                    ]),
              ),
            )),
    );
  }

  InputDecoration _decoracion(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: const Color(0xFFFAFBFD),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: Color(0xFFDCE3EC))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: Color(0xFF176B68), width: 1.6)),
      );
}
