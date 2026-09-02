import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  test('dirFor falls back to system code', () {
    final s = StorageSettings('/roms', {'psx': 'PlayStation'});
    expect(s.dirFor('psx'), '/roms/PlayStation');
    expect(s.dirFor('snes'), '/roms/snes');
  });

  test('gameDir and pathFor put every file inside the game folder', () {
    final s = StorageSettings('/roms', {});
    expect(s.gameDir('snes', 'Mario (USA)'), '/roms/snes/Mario (USA)');
    expect(
      s.pathFor('snes', 'Mario (USA)', 'disc1/a.bin'),
      '/roms/snes/Mario (USA)/disc1/a.bin',
    );
    final mapped = StorageSettings('/roms', {'snes': 'SNES'});
    expect(mapped.gameDir('snes', 'Mario (USA)'), '/roms/SNES/Mario (USA)');
  });

  group('repository', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    test('defaults when empty', () async {
      final s = await StorageSettingsRepository(
        SharedPreferencesAsync(),
      ).load();
      expect(s.baseDir, '/storage/emulated/0/RetroArch/roms');
      expect(s.systemDirs, isEmpty);
    });

    test('persists base dir and system dirs', () async {
      final repo = StorageSettingsRepository(SharedPreferencesAsync());
      await repo.saveBaseDir('/sdcard/roms');
      await repo.saveSystemDir('psx', 'PlayStation');
      await repo.saveSystemDir('snes', 'SNES');
      final s = await repo.load();
      expect(s.baseDir, '/sdcard/roms');
      expect(s.systemDirs, {'psx': 'PlayStation', 'snes': 'SNES'});
    });

    test('providers expose the repository and the settings', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(storageSettingsRepositoryProvider),
        isA<StorageSettingsRepository>(),
      );
      final settings = await container.read(storageSettingsProvider.future);
      expect(settings.baseDir, '/storage/emulated/0/RetroArch/roms');
    });

    test('wifiOnly defaults to false and persists', () async {
      final repo = StorageSettingsRepository(SharedPreferencesAsync());
      expect((await repo.load()).wifiOnly, isFalse);
      await repo.saveWifiOnly(true);
      expect((await repo.load()).wifiOnly, isTrue);
    });
  });
}
