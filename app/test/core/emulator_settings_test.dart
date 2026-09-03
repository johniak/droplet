import 'package:droplet/core/launch/emulator_settings.dart';
import 'package:droplet/core/launch/launch_request.dart';
import 'package:droplet/core/platform/launcher_port.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../fakes/fake_launcher_port.dart';

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  test('choices and tree round-trip', () async {
    final repo = EmulatorSettingsRepository(SharedPreferencesAsync());
    expect(await repo.choice('snes'), isNull);
    await repo.setChoice('snes', 'ra-bsnes');
    expect(await repo.choice('snes'), 'ra-bsnes');
    await repo.setChoice('snes', null);
    expect(await repo.choice('snes'), isNull);
    expect(await repo.romTree(), isNull);
    await repo.saveRomTree(const RomTree(uri: 'content://t', path: '/roms'));
    expect((await repo.romTree())!.path, '/roms');
    // An SD card tree has no path we could compute — the URI still counts.
    await repo.saveRomTree(const RomTree(uri: 'content://sd'));
    expect((await repo.romTree())!.uri, 'content://sd');
    expect((await repo.romTree())!.path, isNull);
  });

  test('effective emulator: choice if installed, else first installed, else null',
      () async {
    final port = FakeLauncherPort(
      installed: {'org.azahar_emu.azahar', 'org.citra.emu'},
    );
    final container = ProviderContainer(
      overrides: [launcherPortProvider.overrideWithValue(port)],
    );
    addTearDown(container.dispose);
    expect(
      (await container.read(effectiveEmulatorProvider('n3ds').future))!.id,
      'azahar',
    );
    await container
        .read(emulatorSettingsRepositoryProvider)
        .setChoice('n3ds', 'citra');
    container.invalidate(emulatorChoiceProvider('n3ds'));
    expect(
      (await container.read(effectiveEmulatorProvider('n3ds').future))!.id,
      'citra',
    );
    // Not installed: the choice is remembered but does not win.
    await container
        .read(emulatorSettingsRepositoryProvider)
        .setChoice('n3ds', 'ra-citra');
    container.invalidate(emulatorChoiceProvider('n3ds'));
    expect(
      (await container.read(effectiveEmulatorProvider('n3ds').future))!.id,
      'azahar',
    );
    expect(await container.read(effectiveEmulatorProvider('switch').future),
        isNull);
    expect(
      (await container.read(installedEmulatorsProvider('n3ds').future))
          .map((s) => s.id),
      ['azahar', 'citra'],
    );
    expect(
      await container.read(installedEmulatorPackagesProvider.future),
      {'org.azahar_emu.azahar', 'org.citra.emu'},
    );
  });

  test('romTreeProvider reads what the repository saved', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(await container.read(romTreeProvider.future), isNull);
    await container
        .read(emulatorSettingsRepositoryProvider)
        .saveRomTree(const RomTree(uri: 'content://t', path: '/roms'));
    container.invalidate(romTreeProvider);
    expect((await container.read(romTreeProvider.future))!.path, '/roms');
  });
}
