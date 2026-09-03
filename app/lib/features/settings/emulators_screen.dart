import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/tokens.dart';
import '../../app/widgets/circle_icon_button.dart';
import '../../app/widgets/glass_panel.dart';
import '../../core/api/models.dart';
import '../../core/launch/emulator_catalog.dart';
import '../../core/launch/emulator_settings.dart';
import '../../core/platform/launcher_port.dart';
import '../library/providers.dart';
import 'settings_screen.dart';

/// Which emulator Play starts, per system — and the folder access most of
/// them need to read a ROM at all.
class EmulatorsScreen extends ConsumerWidget {
  const EmulatorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final systems = ref.watch(systemsProvider).value ?? const <SystemModel>[];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, listBottomPad(context)),
          children: [
            Row(
              children: [
                CircleIconButton(
                  key: const Key('back-button'),
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  onPressed: () => context.pop(),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Emulators',
                  style: TextStyle(
                    color: kText,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const GlassPanel(padding: EdgeInsets.zero, child: _TreeRow()),
            const SizedBox(height: 12),
            GlassPanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final system in systems)
                    if (system.code != kBiosSystemCode) _SystemRow(system: system),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The persisted SAF tree: emulators open the ROM through it, so without it
/// most of them can only refuse.
class _TreeRow extends ConsumerWidget {
  const _TreeRow();

  Future<void> _grant(WidgetRef ref) async {
    final picked = await ref.read(launcherPortProvider).pickRomTree();
    if (picked == null) return;
    await ref.read(emulatorSettingsRepositoryProvider).saveRomTree(picked);
    ref.invalidate(romTreeProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(romTreeProvider).value;
    return SettingsRow(
      title: 'Folder access for emulators',
      subtitle: tree == null
          ? 'Needed by most emulators to open the ROM'
          : 'Granted: ${tree.path ?? tree.uri}',
      trailing: TextButton(
        key: const Key('grant-rom-tree'),
        onPressed: () => _grant(ref),
        child: const Text('Grant'),
      ),
    );
  }
}

class _SystemRow extends ConsumerWidget {
  const _SystemRow({required this.system});

  final SystemModel system;

  Future<void> _select(WidgetRef ref, String id) async {
    await ref
        .read(emulatorSettingsRepositoryProvider)
        .setChoice(system.code, id);
    // `effectiveEmulatorProvider` watches the choice, so it follows on its
    // own — invalidating it too would only rebuild it twice.
    ref.invalidate(emulatorChoiceProvider(system.code));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = catalogFor(system.code);
    if (catalog.isEmpty) {
      return SettingsRow(title: system.name, subtitle: 'No known emulator');
    }
    final installed = ref.watch(installedEmulatorsProvider(system.code)).value;
    if (installed == null) return SettingsRow(title: system.name);
    if (installed.isEmpty) {
      return SettingsRow(
        title: system.name,
        subtitle: 'Not installed: ${catalog.map((s) => s.name).join(', ')}',
      );
    }
    final effective = ref.watch(effectiveEmulatorProvider(system.code)).value;
    return SettingsRow(
      title: system.name,
      trailing: DropdownButton<String>(
        key: Key('emulator-${system.code}'),
        value: effective?.id,
        underline: const SizedBox.shrink(),
        style: const TextStyle(color: kText, fontSize: 14),
        dropdownColor: kBgMid,
        items: [
          for (final spec in installed)
            DropdownMenuItem(value: spec.id, child: Text(spec.name)),
        ],
        // The items carry non-null ids, so the callback never gets null.
        onChanged: (id) => _select(ref, id!),
      ),
    );
  }
}
