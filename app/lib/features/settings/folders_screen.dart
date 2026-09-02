import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/tokens.dart';
import '../../app/widgets/circle_icon_button.dart';
import '../../core/downloads/storage_settings.dart';
import '../library/providers.dart';

/// Podkatalog per system w katalogu ROMów (domyślnie kod systemu).
class FoldersScreen extends ConsumerWidget {
  const FoldersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final systems = ref.watch(systemsProvider).value ?? const [];
    final settings = ref.watch(storageSettingsProvider).value;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, kListBottomPad),
          children: [
            Row(
              children: [
                CircleIconButton(
                  key: const Key('back-button'),
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Wstecz',
                  onPressed: () => context.pop(),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Foldery per system',
                  style: TextStyle(
                    color: kText,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Puste pole = podkatalog o nazwie kodu systemu.',
              style: TextStyle(color: kTextDim, fontSize: 12),
            ),
            const SizedBox(height: 12),
            for (final system in systems)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextFormField(
                  key: Key('system-dir-${system.code}'),
                  initialValue: settings?.systemDirs[system.code] ?? '',
                  style: const TextStyle(color: kText),
                  decoration: InputDecoration(
                    labelText: system.name,
                    hintText: system.code,
                  ),
                  onChanged: (value) async {
                    await ref
                        .read(storageSettingsRepositoryProvider)
                        .saveSystemDir(system.code, value);
                    if (!context.mounted) return;
                    ref.invalidate(storageSettingsProvider);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
