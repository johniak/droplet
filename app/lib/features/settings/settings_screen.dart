import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/tokens.dart';
import '../../app/widgets/glass_panel.dart';
import '../../app/widgets/section_label.dart';
import '../../core/downloads/permissions.dart';
import '../../core/downloads/storage_settings.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/platform/permissions_port.dart';
import '../../core/session/providers.dart';
import '../game/providers.dart';
import '../library/providers.dart';

const appVersion = '0.2.0';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, kListBottomPad),
            children: const [
              Text(
                'Ustawienia',
                style: TextStyle(
                  color: kText,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
              SizedBox(height: 12),
              _ServerCard(),
              SectionLabel('Pobieranie'),
              _DownloadCard(),
              SectionLabel('Urządzenie'),
              _DeviceCard(),
              SectionLabel('O aplikacji'),
              GlassPanel(
                padding: EdgeInsets.zero,
                child: SettingsRow(
                  title: 'Droplet $appVersion',
                  trailing: Text('API v1', style: TextStyle(color: kTextDim)),
                ),
              ),
            ],
          ),
        ),
      );
}

/// Jeden wiersz karty ustawień.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 10)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(color: kText, fontSize: 14),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style:
                              const TextStyle(color: kTextDim, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, indent: 14, endIndent: 14);
}

class _ServerCard extends ConsumerWidget {
  const _ServerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    final offline = ref.watch(isOfflineProvider);
    final snapshot = ref.watch(librarySnapshotProvider).value;
    final counts = snapshot == null
        ? ''
        : ' · ${snapshot.games.length} gier · ${snapshot.systems.length} systemów';
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingsRow(
            leading: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: offline ? kTextDim : kOk,
                shape: BoxShape.circle,
                boxShadow: offline
                    ? null
                    : [
                        BoxShadow(
                          color: kOk.withValues(alpha: 0.7),
                          blurRadius: 10,
                        ),
                      ],
              ),
            ),
            title: offline ? 'Offline' : 'Połączono',
            subtitle: session == null
                ? 'Nie zalogowano'
                : '${session.serverUrl}$counts',
          ),
          const _Divider(),
          SettingsRow(
            title: 'Wyloguj',
            trailing: const Icon(Icons.logout, size: 18, color: kTextDim),
            onTap: () => ref.read(sessionProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }
}

class _DownloadCard extends ConsumerWidget {
  const _DownloadCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(storageSettingsProvider);
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: settings.when(
        loading: () => const SettingsRow(title: '...'),
        error: (e, _) => SettingsRow(title: humanizeError(e)),
        data: (data) => Column(
          children: [
            SettingsRow(
              title: 'Katalog ROMów',
              subtitle: data.baseDir,
              trailing: TextButton(
                onPressed: () => _editBaseDir(context, ref, data.baseDir),
                child: const Text('Zmień'),
              ),
            ),
            const _Divider(),
            _PermissionRow(baseDir: data.baseDir),
            const _Divider(),
            SettingsRow(
              title: 'Foldery per system',
              subtitle: data.systemDirs.isEmpty
                  ? 'domyślne'
                  : data.systemDirs.keys.join(', '),
              trailing: const Icon(Icons.chevron_right, color: kTextDim),
              onTap: () => context.go('/settings/folders'),
            ),
            const _Divider(),
            SettingsRow(
              title: 'Pobieraj tylko po Wi‑Fi',
              trailing: Switch(
                key: const Key('wifi-only'),
                value: data.wifiOnly,
                onChanged: (v) async {
                  await ref
                      .read(storageSettingsRepositoryProvider)
                      .saveWifiOnly(v);
                  ref.invalidate(storageSettingsProvider);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editBaseDir(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => _BaseDirDialog(current: current),
    );
    if (value == null || value.isEmpty) return;
    await ref.read(storageSettingsRepositoryProvider).saveBaseDir(value);
    ref.invalidate(storageSettingsProvider);
  }
}

/// Osobny widget na dialog: kontroler żyje w jego własnym `State`, więc jest
/// zwalniany dopiero po pełnym zdjęciu route'a — nie w trakcie animacji
/// zamykania, co powodowałoby użycie już zdysponowanego kontrolera.
class _BaseDirDialog extends StatefulWidget {
  const _BaseDirDialog({required this.current});

  final String current;

  @override
  State<_BaseDirDialog> createState() => _BaseDirDialogState();
}

class _BaseDirDialogState extends State<_BaseDirDialog> {
  late final _controller = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Katalog ROMów'),
        content: TextField(
          key: const Key('base-dir-field'),
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            helperText: 'Katalog RetroArch na telefonie',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_controller.text.trim()),
            child: const Text('Zapisz'),
          ),
        ],
      );
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

  @override
  void didUpdateWidget(covariant _PermissionRow old) {
    super.didUpdateWidget(old);
    if (old.baseDir != widget.baseDir) _refresh();
  }

  Future<void> _refresh() async {
    final port = ref.read(permissionsPortProvider);
    final needed =
        needsAllFilesAccess(widget.baseDir, await port.appPrivateDirs());
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
  Widget build(BuildContext context) => SettingsRow(
        title: 'Dostęp do plików',
        subtitle: _granted == true ? 'Przyznany' : 'Brak',
        trailing: _granted == true
            ? const Icon(Icons.check_rounded, color: kAccent, size: 18)
            : TextButton(
                key: const Key('grant-permission'),
                onPressed: _grant,
                child: const Text('Przyznaj'),
              ),
      );
}

class _DeviceCard extends ConsumerWidget {
  const _DeviceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseDir = ref.watch(storageSettingsProvider).value?.baseDir;
    final free =
        baseDir == null ? null : ref.watch(freeBytesProvider(baseDir)).value;
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: SettingsRow(
        title: 'Wolne miejsce',
        trailing: Text(
          free == null ? '—' : formatBytes(free),
          style: const TextStyle(color: kTextDim),
        ),
      ),
    );
  }
}
