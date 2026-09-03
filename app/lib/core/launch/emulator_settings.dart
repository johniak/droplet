import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/launcher_port.dart';
import 'emulator_catalog.dart';
import 'launch_request.dart';

const _kTreeUri = 'rom_tree_uri';
const _kTreePath = 'rom_tree_path';

String _choiceKey(String systemCode) => 'emulator.$systemCode';

/// Per-system emulator choice and the SAF tree the emulators read ROMs
/// through — both in SharedPreferences, like the storage settings.
class EmulatorSettingsRepository {
  EmulatorSettingsRepository(this._prefs);

  final SharedPreferencesAsync _prefs;

  Future<String?> choice(String systemCode) =>
      _prefs.getString(_choiceKey(systemCode));

  /// `null` clears the choice, so the default (first installed) takes over
  /// again.
  Future<void> setChoice(String systemCode, String? id) => id == null
      ? _prefs.remove(_choiceKey(systemCode))
      : _prefs.setString(_choiceKey(systemCode), id);

  Future<RomTree?> romTree() async {
    final uri = await _prefs.getString(_kTreeUri);
    if (uri == null) return null;
    return RomTree(uri: uri, path: await _prefs.getString(_kTreePath));
  }

  Future<void> saveRomTree(RomTree tree) async {
    await _prefs.setString(_kTreeUri, tree.uri);
    // A tree outside internal storage has no path we can compute; the stale
    // one from an earlier grant must not survive it.
    final path = tree.path;
    if (path == null) {
      await _prefs.remove(_kTreePath);
    } else {
      await _prefs.setString(_kTreePath, path);
    }
  }
}

final emulatorSettingsRepositoryProvider = Provider<EmulatorSettingsRepository>(
  (ref) => EmulatorSettingsRepository(SharedPreferencesAsync()),
);

final romTreeProvider = FutureProvider<RomTree?>(
  (ref) => ref.watch(emulatorSettingsRepositoryProvider).romTree(),
);

/// Which of the catalogue's packages are on this device — one call for the
/// whole catalogue.
final installedEmulatorPackagesProvider = FutureProvider<Set<String>>(
  (ref) async => (await ref
          .watch(launcherPortProvider)
          .installedPackages(allCatalogPackages.toList()))
      .toSet(),
);

/// The catalogue for a system, narrowed to what is installed — catalogue
/// order, so the first entry is the preferred one.
final installedEmulatorsProvider =
    FutureProvider.family<List<EmulatorSpec>, String>((ref, code) async {
      final installed = await ref.watch(installedEmulatorPackagesProvider.future);
      return [
        for (final spec in catalogFor(code))
          if (installed.contains(spec.package)) spec,
      ];
    });

final emulatorChoiceProvider = FutureProvider.family<String?, String>(
  (ref, code) => ref.watch(emulatorSettingsRepositoryProvider).choice(code),
);

/// What Play would start: the chosen emulator while it is installed, else
/// the first installed one, else nothing.
final effectiveEmulatorProvider =
    FutureProvider.family<EmulatorSpec?, String>((ref, code) async {
      final installed = await ref.watch(installedEmulatorsProvider(code).future);
      if (installed.isEmpty) return null;
      final chosen = await ref.watch(emulatorChoiceProvider(code).future);
      return installed.firstWhere(
        (spec) => spec.id == chosen,
        orElse: () => installed.first,
      );
    });
