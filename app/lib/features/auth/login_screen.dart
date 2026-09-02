import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tokens.dart';
import '../../app/widgets/glass_panel.dart';
import '../../app/widgets/primary_button.dart';
import '../../core/api/api_client.dart';
import '../../core/errors.dart';
import '../../core/session/providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _server = TextEditingController(text: 'http://');
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _required(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Wymagane' : null;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .signIn(_server.text.trim(), _username.text, _password.text);
    } catch (e) {
      setState(() => _error = _messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _messageFor(Object e) {
    if (e is UnauthorizedException) return 'Błędny login lub hasło';
    if (e is DioException && e.response?.statusCode == 400) {
      return 'Błędny login lub hasło';
    }
    return humanizeError(e);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: kPrimaryGradient,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: kAccent.withValues(alpha: 0.45),
                            blurRadius: 40,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.water_drop_rounded,
                          color: Colors.white, size: 32),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Droplet',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: kText,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Twoja biblioteka ROMów',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kTextDim),
                  ),
                  const SizedBox(height: 28),
                  GlassPanel(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _server,
                            decoration: const InputDecoration(
                              labelText: 'Adres serwera',
                              hintText: 'http://192.168.1.10:8000',
                            ),
                            keyboardType: TextInputType.url,
                            validator: _required,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _username,
                            decoration:
                                const InputDecoration(labelText: 'Login'),
                            validator: _required,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            decoration:
                                const InputDecoration(labelText: 'Hasło'),
                            obscureText: true,
                            validator: _required,
                          ),
                          const SizedBox(height: 18),
                          PrimaryButton(
                            label: 'Zaloguj',
                            busy: _busy,
                            onPressed: _busy ? null : _submit,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: kDanger),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Hasło zostaje na telefonie, appka trzyma tylko token.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kTextDim, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
