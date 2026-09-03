import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kBaseDir = 'storage.base_dir';
const _kSystemDirs = 'storage.system_dirs';
const _kWifiOnly = 'storage.wifi_only';
const defaultBaseDir = '/storage/emulated/0/RetroArch/roms';

/// Nadpisanie katalogu systemu to **jedna nazwa katalogu**. Separator albo
/// segment „..” wyprowadziłby ścieżki gier poza katalog ROMów — a wtedy skan i
/// „Usuń wszystko" pracowałyby na cudzym drzewie. Puste pole to nie wartość,
/// tylko brak nadpisania, więc odsiewa je [normalizeSystemDir].
bool isValidSystemDir(String dir) =>
    !dir.contains('/') &&
    !dir.contains(r'\') &&
    !RegExp(r'^\.+$').hasMatch(dir);

/// Przycięta nazwa katalogu albo `null`, gdy nadpisania ma nie być (puste pole)
/// lub gdy wartość jest niebezpieczna.
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

  /// system code -> subdirectory; no entry means the code itself. Puste i
  /// niebezpieczne wartości nie mają tu wstępu (patrz konstruktor).
  final Map<String, String> systemDirs;

  /// Kolejkuj pobierania tylko na Wi‑Fi (flaga `requiresWiFi` taska).
  final bool wifiOnly;

  String dirFor(String systemCode) =>
      '$baseDir/${systemDirs[systemCode] ?? systemCode}';

  /// Katalog jednej gry — wszystkie jej pliki mieszkają w środku.
  String gameDir(String systemCode, String folder) =>
      '${dirFor(systemCode)}/$folder';

  /// [fileName] to nazwa względem katalogu gry, więc może zawierać podkatalog.
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

  /// Puste pole kasuje nadpisanie, wartość niebezpieczna nie zapisuje się
  /// wcale — poprzednia zostaje, bo pole edytuje się znak po znaku i „SNES/”
  /// w połowie wpisywania nie ma wywalać ustawienia.
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
