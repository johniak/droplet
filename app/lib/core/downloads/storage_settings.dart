import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kBaseDir = 'storage.base_dir';
const _kSystemDirs = 'storage.system_dirs';
const defaultBaseDir = '/storage/emulated/0/RetroArch/roms';

class StorageSettings {
  StorageSettings(this.baseDir, this.systemDirs);

  final String baseDir;

  /// system code -> subdirectory; no entry means the code itself.
  final Map<String, String> systemDirs;

  String dirFor(String systemCode) =>
      '$baseDir/${systemDirs[systemCode] ?? systemCode}';

  String pathFor(String systemCode, String fileName) =>
      '${dirFor(systemCode)}/$fileName';
}

class StorageSettingsRepository {
  StorageSettingsRepository(this._prefs);

  final SharedPreferencesAsync _prefs;

  Future<StorageSettings> load() async {
    final baseDir = await _prefs.getString(_kBaseDir) ?? defaultBaseDir;
    final raw = await _prefs.getString(_kSystemDirs);
    final dirs = raw == null
        ? <String, String>{}
        : (jsonDecode(raw) as Map).cast<String, String>();
    return StorageSettings(baseDir, dirs);
  }

  Future<void> saveBaseDir(String dir) => _prefs.setString(_kBaseDir, dir);

  Future<void> saveSystemDir(String code, String dir) async {
    final settings = await load();
    final dirs = Map<String, String>.from(settings.systemDirs)..[code] = dir;
    await _prefs.setString(_kSystemDirs, jsonEncode(dirs));
  }
}

final storageSettingsRepositoryProvider = Provider<StorageSettingsRepository>(
  (ref) => StorageSettingsRepository(SharedPreferencesAsync()),
);

final storageSettingsProvider = FutureProvider<StorageSettings>(
  (ref) => ref.watch(storageSettingsRepositoryProvider).load(),
);
