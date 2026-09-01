import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_client.dart';
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
    return 'Nie mogę połączyć z serwerem';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Droplet',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          color: kText,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -1,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Twoja biblioteka ROMów',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kTextDim),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _server,
                    decoration: const InputDecoration(
                      labelText: 'Adres serwera',
                      hintText: 'http://192.168.1.10:8000',
                    ),
                    keyboardType: TextInputType.url,
                    validator: _required,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _username,
                    decoration: const InputDecoration(labelText: 'Login'),
                    validator: _required,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    decoration: const InputDecoration(labelText: 'Hasło'),
                    obscureText: true,
                    validator: _required,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Zaloguj'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFF07178)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
