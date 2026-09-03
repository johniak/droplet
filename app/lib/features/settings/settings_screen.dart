import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/tokens.dart';
import '../../app/widgets/glass_panel.dart';
import '../../app/widgets/pill.dart';
import '../../app/widgets/section_label.dart';
import '../../core/api/models.dart';
import '../../core/downloads/device_scan.dart';
import '../../core/downloads/local_state.dart';
import '../../core/downloads/permissions.dart';
import '../../core/downloads/storage_settings.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/platform/folder_picker_port.dart';
import '../../core/platform/permissions_port.dart';
import '../../core/session/providers.dart';
import '../game/providers.dart';
import '../library/providers.dart';

const appVersion = '0.5.6';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 10, 16, listBottomPad(context)),
        children: const [
          Text(
            'Settings',
            style: TextStyle(
              color: kText,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          SizedBox(height: 12),
          _ServerCard(),
          SectionLabel('Downloads'),
          _DownloadCard(),
          SectionLabel('System files'),
          _SystemFilesCard(),
          SectionLabel('Device'),
          _DeviceCard(),
          SectionLabel('About'),
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

/// One row of a settings card.
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
                      style: const TextStyle(color: kTextDim, fontSize: 12),
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

String _count(int n, String noun) => n == 1 ? '1 $noun' : '$n ${noun}s';

class _ServerCard extends ConsumerWidget {
  const _ServerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    final offline = ref.watch(isOfflineProvider);
    final snapshot = ref.watch(librarySnapshotProvider).value;
    final counts = snapshot == null
        ? ''
        : ' · ${_count(snapshot.games.length, 'game')}'
              ' · ${_count(snapshot.systems.length, 'system')}';
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
            title: offline ? 'Offline' : 'Connected',
            subtitle: session == null
                ? 'Not signed in'
                : '${session.serverUrl}$counts',
          ),
          const _Divider(),
          SettingsRow(
            title: 'Sign out',
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
              title: 'ROM folder',
              subtitle: data.baseDir,
              trailing: TextButton(
                onPressed: () => _editBaseDir(context, ref, data.baseDir),
                child: const Text('Change'),
              ),
            ),
            const _Divider(),
            _PermissionRow(baseDir: data.baseDir),
            const _Divider(),
            SettingsRow(
              title: 'Folders per system',
              subtitle: data.systemDirs.isEmpty
                  ? 'default'
                  : data.systemDirs.keys.join(', '),
              trailing: const Icon(Icons.chevron_right, color: kTextDim),
              onTap: () => context.go('/settings/folders'),
            ),
            const _Divider(),
            SettingsRow(
              title: 'Download over Wi‑Fi only',
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

/// A separate widget for the dialog: the controller lives in its own `State`,
/// so it is disposed only once the route is fully popped — not during the
/// closing animation, which would mean using an already disposed controller.
class _BaseDirDialog extends ConsumerStatefulWidget {
  const _BaseDirDialog({required this.current});

  final String current;

  @override
  ConsumerState<_BaseDirDialog> createState() => _BaseDirDialogState();
}

class _BaseDirDialogState extends ConsumerState<_BaseDirDialog> {
  late final _controller = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The system folder picker; a cancelled pick leaves the field alone, so
  /// typing the path by hand stays possible (SD cards come back as `null`).
  Future<void> _browse() async {
    final picked = await ref.read(folderPickerPortProvider).pickDirectory();
    if (picked == null || !mounted) return;
    setState(() => _controller.text = picked);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('ROM folder'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('base-dir-field'),
          controller: _controller,
          decoration: const InputDecoration(
            helperText: 'Where your emulators keep ROMs',
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('browse-folder'),
          onPressed: _browse,
          icon: const Icon(Icons.folder_open),
          label: const Text('Browse'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        child: const Text('Save'),
      ),
    ],
  );
}

/// `Installed` / `Partial` for a support pack — the same words the game
/// detail screen uses, minus "Update available": packs have no update role.
String? _packPillText(LocalGameState state) => switch (state.status) {
  InstallStatus.installed => 'Installed',
  InstallStatus.partial => 'Partial',
  InstallStatus.none => null,
};

/// BIOS, firmware and key packs — games of the `bios` system, kept out of
/// the library shelves and shown here instead (see `LibrarySnapshot`).
class _SystemFilesCard extends ConsumerWidget {
  const _SystemFilesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(librarySnapshotProvider).value;
    if (snapshot == null) {
      // Loading: no snapshot yet to tell an empty library from one full of
      // packs — an empty card beats a wrong guess either way.
      return const GlassPanel(
        padding: EdgeInsets.zero,
        child: SizedBox.shrink(),
      );
    }
    final packs = snapshot.supportPacks;
    final settings = ref.watch(storageSettingsProvider).value;
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          if (packs.isEmpty)
            const SettingsRow(
              title: 'No system files on the server',
              subtitle:
                  'Put BIOS or firmware packs in bios/<pack>/ on the server',
            )
          else ...[
            for (var i = 0; i < packs.length; i++) ...[
              if (i > 0) const _Divider(),
              _packRow(context, ref, packs[i], snapshot.manifest),
            ],
            if (settings != null) ...[
              const _Divider(),
              SettingsRow(
                title:
                    'Point your emulator at '
                    '${settings.dirFor(kBiosSystemCode)}/<pack>',
                trailing: TextButton(
                  onPressed: () => _copyBiosPath(context, settings),
                  child: const Text('Copy path'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _packRow(
    BuildContext context,
    WidgetRef ref,
    GameSummary pack,
    List<ManifestEntry> manifest,
  ) {
    final local = ref.watch(localStateProvider(pack.id)).value;
    final fileCount = manifest
        .where((e) => e.gameId == pack.id)
        .fold(0, (sum, e) => sum + e.files.length);
    final pillText = local == null ? null : _packPillText(local);
    return SettingsRow(
      title: pack.title,
      subtitle: '${_count(fileCount, 'file')} · ${formatBytes(pack.totalSize)}',
      trailing: pillText == null ? null : Pill(pillText, accent: true),
      onTap: () => context.push('/settings/game/${pack.id}'),
    );
  }

  Future<void> _copyBiosPath(
    BuildContext context,
    StorageSettings settings,
  ) async {
    await Clipboard.setData(
      ClipboardData(text: settings.dirFor(kBiosSystemCode)),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Path copied')));
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

  @override
  void didUpdateWidget(covariant _PermissionRow old) {
    super.didUpdateWidget(old);
    if (old.baseDir != widget.baseDir) _refresh();
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
  Widget build(BuildContext context) => SettingsRow(
    title: 'File access',
    subtitle: _granted == true ? 'Granted' : 'None',
    trailing: _granted == true
        ? const Icon(Icons.check_rounded, color: kAccent, size: 18)
        : TextButton(
            key: const Key('grant-permission'),
            onPressed: _grant,
            child: const Text('Grant'),
          ),
  );
}

class _DeviceCard extends ConsumerWidget {
  const _DeviceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(storageSettingsProvider).value;
    final free = settings == null
        ? null
        : ref.watch(freeBytesProvider(settings.baseDir)).value;
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingsRow(
            title: 'Free space',
            trailing: Text(
              free == null ? '—' : formatBytes(free),
              style: const TextStyle(color: kTextDim),
            ),
          ),
          const _Divider(),
          _UnknownRow(settings: settings),
        ],
      ),
    );
  }
}

String pluralPositions(int n) => n == 1 ? '1 item' : '$n items';

/// Deletes only entries under the ROM folder — and not just any of them:
/// a `..` in the path would take the delete outside the tree despite a
/// matching prefix, and a system folder itself is never an "unknown entry"
/// (it would be one only after a bad overwrite, and would take the whole
/// collection with it).
void deleteUnknown(
  List<UnknownEntry> entries,
  StorageSettings settings,
  Iterable<String> systemCodes,
) {
  final baseDir = settings.baseDir;
  final systemDirs = {for (final code in systemCodes) settings.dirFor(code)};
  for (final e in entries) {
    if (!insideBaseDir(e.path, baseDir)) continue;
    if (systemDirs.contains(e.path)) continue;
    if (e.isDirectory) {
      final d = Directory(e.path);
      if (d.existsSync()) d.deleteSync(recursive: true);
    } else {
      final f = File(e.path);
      if (f.existsSync()) f.deleteSync();
    }
  }
}

/// The path shown to the user: relative to the ROM folder, or in full when
/// the entry lies outside it (and will not be deleted anyway).
String displayPath(String path, String baseDir) =>
    path.startsWith('$baseDir/') ? path.substring(baseDir.length + 1) : path;

String _summary(List<UnknownEntry> entries) =>
    '${pluralPositions(entries.length)} · '
    '${formatBytes(entries.fold(0, (a, e) => a + e.bytes))}';

/// Files and folders in the ROM tree that no game in the library knows —
/// usually leftovers from the layout before per-game folders.
class _UnknownRow extends ConsumerWidget {
  const _UnknownRow({required this.settings});

  final StorageSettings? settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unknown = ref.watch(unknownOnDeviceProvider);
    // Without settings (still loading) there is nothing to delete, so the row
    // is not tappable — and does not fake it with a chevron.
    final open = unknown.isEmpty || settings == null
        ? null
        : () => _showUnknown(context, ref, unknown, settings!);
    return SettingsRow(
      key: const Key('unknown-on-device'),
      title: 'Unknown on device',
      subtitle: unknown.isEmpty ? 'None' : _summary(unknown),
      trailing: open == null
          ? null
          : const Icon(Icons.chevron_right, color: kTextDim),
      onTap: open,
    );
  }

  Future<void> _showUnknown(
    BuildContext context,
    WidgetRef ref,
    List<UnknownEntry> unknown,
    StorageSettings settings,
  ) async {
    final baseDir = settings.baseDir;
    final shown = unknown.take(50).toList();
    // "Unknown" means "not in the manifest" — and with an empty manifest
    // (library not synced yet) *everything* is unknown. A bulk delete would
    // then wipe the whole collection, so the button is disabled.
    final snapshot = ref.read(librarySnapshotProvider).value;
    final manifest = snapshot?.manifest ?? const [];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unknown on device'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                _summary(unknown),
                style: const TextStyle(color: kText, fontSize: 13),
              ),
              if (manifest.isEmpty)
                const Text(
                  'Sync the library from the server first',
                  style: TextStyle(color: kDanger, fontSize: 13),
                ),
              const SizedBox(height: 8),
              for (final e in shown)
                Text(
                  displayPath(e.path, baseDir),
                  style: const TextStyle(color: kTextDim, fontSize: 13),
                ),
              if (unknown.length > shown.length)
                Text(
                  '… and ${unknown.length - shown.length} more',
                  style: const TextStyle(color: kTextDim, fontSize: 13),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Close'),
          ),
          TextButton(
            key: const Key('unknown-delete-all'),
            onPressed: manifest.isEmpty
                ? null
                : () => Navigator.of(context).pop(true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    deleteUnknown(unknown, settings, [
      for (final s in snapshot?.systems ?? const []) s.code,
    ]);
    await ref.read(deviceIndexProvider.notifier).refresh();
  }
}
