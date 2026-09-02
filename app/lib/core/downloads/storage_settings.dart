import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kBaseDir = 'storage.base_dir';
const _kSystemDirs = 'storage.system_dirs';
const _kWifiOnly = 'storage.wifi_only';
const defaultBaseDir = '/storage/emulated/0/RetroArch/roms';

class StorageSettings {
  StorageSettings(this.baseDir, this.systemDirs, {this.wifiOnly = false});

  final String baseDir;

  /// system code -> subdirectory; no entry means the code itself.
  final Map<String, String> systemDirs;

  /// Kolejkuj pobierania tylko na Wi‑Fi (flaga `requiresWiFi` taska).
  final bool wifiOnly;

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
    final wifiOnly = await _prefs.getBool(_kWifiOnly) ?? false;
    return StorageSettings(baseDir, dirs, wifiOnly: wifiOnly);
  }

  Future<void> saveBaseDir(String dir) => _prefs.setString(_kBaseDir, dir);

  Future<void> saveSystemDir(String code, String dir) async {
    final settings = await load();
    final dirs = Map<String, String>.from(settings.systemDirs)..[code] = dir;
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
