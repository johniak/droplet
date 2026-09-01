import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/session/providers.dart';

const appVersion = '0.1.0';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Ustawienia')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const _SectionLabel('Serwer'),
          ListTile(
            title: Text(
              session?.serverUrl ?? 'Nie zalogowano',
              style: const TextStyle(color: kText),
            ),
            subtitle: const Text(
              'Adres backendu Dropletu',
              style: TextStyle(color: kTextDim),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: kTextDim),
            title: const Text('Wyloguj', style: TextStyle(color: kText)),
            onTap: () => ref.read(sessionProvider.notifier).signOut(),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('O aplikacji'),
          const ListTile(
            title: Text('Droplet', style: TextStyle(color: kText)),
            subtitle: Text(
              'wersja $appVersion',
              style: TextStyle(color: kTextDim),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: kAccent,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      );
}
