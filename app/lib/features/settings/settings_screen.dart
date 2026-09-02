import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/downloads/permissions.dart';
import '../../core/errors.dart';
import '../../core/downloads/storage_settings.dart';
import '../../core/platform/permissions_port.dart';
import '../../core/session/providers.dart';
import '../library/providers.dart';

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
          const _SectionLabel('Pobieranie'),
          const _DownloadSection(),
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
          text,
          style: const TextStyle(
            color: kAccent,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      );
}


class _DownloadSection extends ConsumerWidget {
  const _DownloadSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(storageSettingsProvider);
    return settings.when(
      loading: () => const ListTile(title: Text('...')),
      error: (e, _) => ListTile(
        title: Text(humanizeError(e), style: const TextStyle(color: kTextDim)),
      ),
      data: (data) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PermissionRow(baseDir: data.baseDir),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: TextFormField(
              key: const Key('base-dir-field'),
              initialValue: data.baseDir,
              style: const TextStyle(color: kText),
              decoration: const InputDecoration(
                labelText: 'Katalog ROMów',
                helperText: 'Katalog RetroArch na telefonie',
              ),
              // Saved on every keystroke: the e2e run types a path and leaves
              // the screen immediately.
              onChanged: (value) => ref
                  .read(storageSettingsRepositoryProvider)
                  .saveBaseDir(value),
            ),
          ),
          const _SystemDirs(),
        ],
      ),
    );
  }
}

class _PermissionRow extends ConsumerStatefulWidget {
  const _PermissionRow({required this.baseDir});

  final String baseDir;

  @override
  ConsumerState<_PermissionRow> createState() => _PermissionRowState();
}

class _PermissionRowState extends ConsumerState<_PermissionRow> {
  bool? _granted;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final port = ref.read(permissionsPortProvider);
    final needed = needsAllFilesAccess(
      widget.baseDir,
      await port.appPrivateDirs(),
    );
    final granted = !needed || await port.hasAllFilesAccess();
    if (mounted) setState(() => _granted = granted);
  }

  Future<void> _grant() async {
    await ensureStoragePermission(
      ref.read(permissionsPortProvider),
      widget.baseDir,
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) => ListTile(
        title: const Text(
          'Dostęp do plików',
          style: TextStyle(color: kText),
        ),
        subtitle: Text(
          _granted == true ? 'Przyznane' : 'Brak',
          style: TextStyle(color: _granted == true ? kAccent : kTextDim),
        ),
        trailing: _granted == true
            ? null
            : TextButton(
                key: const Key('grant-permission'),
                onPressed: _grant,
                child: const Text('Przyznaj'),
              ),
      );
}

class _SystemDirs extends ConsumerWidget {
  const _SystemDirs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final systems = ref.watch(systemsProvider);
    final settings = ref.watch(storageSettingsProvider).value;
    return Column(
      children: systems.maybeWhen(
        data: (list) => [
          for (final system in list)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: TextFormField(
                key: Key('system-dir-${system.code}'),
                initialValue: settings?.systemDirs[system.code] ?? '',
                style: const TextStyle(color: kText),
                decoration: InputDecoration(
                  labelText: system.name,
                  hintText: system.code,
                ),
                onChanged: (value) => ref
                    .read(storageSettingsRepositoryProvider)
                    .saveSystemDir(system.code, value),
              ),
            ),
        ],
        orElse: () => const <Widget>[],
      ),
    );
  }
}
