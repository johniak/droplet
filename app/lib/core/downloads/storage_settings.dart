import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kBaseDir = 'storage.base_dir';
const _kSystemDirs = 'storage.system_dirs';
const _kWifiOnly = 'storage.wifi_only';
const defaultBaseDir = '/storage/emulated/0/RetroArch/roms';

/// A system directory override is **a single directory name**. A separator or
/// a '..' segment would take game paths outside the ROM folder — and then the
/// scan and "Delete all" would work on someone else's tree. An empty field is
/// not a value but the absence of an override, so [normalizeSystemDir] drops
/// it.
bool isValidSystemDir(String dir) =>
    !dir.contains('/') &&
    !dir.contains(r'\') &&
    !RegExp(r'^\.+$').hasMatch(dir);

/// The trimmed directory name, or `null` when there should be no override
/// (empty field) or when the value is unsafe.
String? normalizeSystemDir(String dir) {
  final value = dir.trim();
  return value.isEmpty || !isValidSystemDir(value) ? null : value;
}

class StorageSettings {
  StorageSettings(
    this.baseDir,
    Map<String, String> systemDirs, {
    this.wifiOnly = false,
  }) : systemDirs = {
          for (final e in systemDirs.entries)
            if (normalizeSystemDir(e.value) case final dir?) e.key: dir,
        };

  final String baseDir;

  /// system code -> subdirectory; no entry means the code itself. Empty and
  /// unsafe values never get in here (see the constructor).
  final Map<String, String> systemDirs;

  /// Queue downloads on Wi‑Fi only (the task's `requiresWiFi` flag).
  final bool wifiOnly;

  String dirFor(String systemCode) =>
      '$baseDir/${systemDirs[systemCode] ?? systemCode}';

  /// One game's folder — all of its files live inside.
  String gameDir(String systemCode, String folder) =>
      '${dirFor(systemCode)}/$folder';

  /// [fileName] is relative to the game folder, so it may hold a subfolder.
  String pathFor(String systemCode, String folder, String fileName) =>
      '${gameDir(systemCode, folder)}/$fileName';
}

class StorageSettingsRepository {
  StorageSettingsRepository(this._prefs);

  final SharedPreferencesAsync _prefs;

  Future<StorageSettings> load() async {
    final baseDir = await _prefs.getString(_kBaseDir) ?? defaultBaseDir;
    final raw = await _prefs.getString(_kSystemDirs);
    final dirs = raw == null
        ? const <String, String>{}
        : (jsonDecode(raw) as Map).cast<String, String>();
    final wifiOnly = await _prefs.getBool(_kWifiOnly) ?? false;
    return StorageSettings(baseDir, dirs, wifiOnly: wifiOnly);
  }

  Future<void> saveBaseDir(String dir) => _prefs.setString(_kBaseDir, dir);

  /// An empty field clears the override; an unsafe value is not saved at all
  /// — the previous one stays, because the field is edited character by
  /// character and a half-typed "SNES/" must not wipe the setting.
  Future<void> saveSystemDir(String code, String dir) async {
    final value = dir.trim();
    if (value.isNotEmpty && !isValidSystemDir(value)) return;
    final settings = await load();
    final dirs = Map<String, String>.from(settings.systemDirs);
    if (value.isEmpty) {
      dirs.remove(code);
    } else {
      dirs[code] = value;
    }
    await _prefs.setString(_kSystemDirs, jsonEncode(dirs));
  }

  Future<void> saveWifiOnly(bool value) => _prefs.setBool(_kWifiOnly, value);
}

final storageSettingsRepositoryProvider = Provider<StorageSettingsRepository>(
  (ref) => StorageSettingsRepository(SharedPreferencesAsync()),
);

final storageSettingsProvider = FutureProvider<StorageSettings>(
  (ref) => ref.watch(storageSettingsRepositoryProvider).load(),
);
