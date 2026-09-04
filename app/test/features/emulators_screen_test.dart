import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/launch/emulator_settings.dart';
import 'package:droplet/core/launch/launch_request.dart';
import 'package:droplet/core/platform/launcher_port.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:droplet/features/settings/emulators_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../fakes/fake_launcher_port.dart';

const _systems = [
  SystemModel(id: 1, code: 'switch', name: 'Switch', gameCount: 1),
  SystemModel(id: 2, code: 'n3ds', name: 'Nintendo 3DS', gameCount: 1),
  SystemModel(id: 3, code: 'snes', name: 'SNES', gameCount: 1),
  // No catalogue entries at all...
  SystemModel(id: 4, code: 'arcade', name: 'Arcade', gameCount: 1),
  // ...and support packs are not games, so they never get a row.
  SystemModel(id: 5, code: 'bios', name: 'System files', gameCount: 1),
];

GoRouter _router() => GoRouter(
  initialLocation: '/settings/emulators',
  routes: [
    GoRoute(
      path: '/settings',
      builder: (_, __) => const Scaffold(body: Text('Settings')),
      routes: [
        GoRoute(
          path: 'emulators',
          builder: (_, __) => const EmulatorsScreen(),
        ),
      ],
    ),
  ],
);

Widget _app(FakeLauncherPort port, EmulatorSettingsRepository repo) =>
    ProviderScope(
      overrides: [
        launcherPortProvider.overrideWithValue(port),
        emulatorSettingsRepositoryProvider.overrideWithValue(repo),
        systemsProvider.overrideWith((ref) async => _systems),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    );

void main() {
  late EmulatorSettingsRepository repo;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    repo = EmulatorSettingsRepository(SharedPreferencesAsync());
  });

  testWidgets('nothing installed: every system names what it would need', (
    tester,
  ) async {
    await tester.pumpWidget(_app(FakeLauncherPort(), repo));
    await tester.pumpAndSettle();
    expect(find.text('Emulators'), findsOneWidget);
    expect(
      find.text('Not installed: Eden, Citron, Sudachi, Yuzu, Kenji-NX'),
      findsOneWidget,
    );
    expect(
      find.text('Not installed: RetroArch (Snes9x), RetroArch (bsnes)'),
      findsOneWidget,
    );
    expect(find.text('No known emulator'), findsOneWidget);
    expect(find.text('System files'), findsNothing);
    expect(find.byType(DropdownButton<String>), findsNothing);
    // Without a granted tree the row says what the button is for.
    expect(
      find.text('Needed by most emulators to open the ROM'),
      findsOneWidget,
    );
  });

  testWidgets('installed emulators land in a dropdown and the pick sticks', (
    tester,
  ) async {
    final port = FakeLauncherPort(
      installed: {'org.azahar_emu.azahar', 'org.citra.emu'},
    );
    await tester.pumpWidget(_app(port, repo));
    await tester.pumpAndSettle();
    final dropdown = find.byKey(const Key('emulator-n3ds'));
    expect(dropdown, findsOneWidget);
    // The default is the first installed emulator in catalogue order.
    expect(
      tester.widget<DropdownButton<String>>(dropdown).value,
      'azahar',
    );
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Citra MMJ').last);
    await tester.pumpAndSettle();
    expect(await repo.choice('n3ds'), 'citra-mmj');
    expect(tester.widget<DropdownButton<String>>(dropdown).value, 'citra-mmj');
  });

  testWidgets('Grant stores the picked tree; a cancelled pick changes nothing',
      (tester) async {
    final port = FakeLauncherPort();
    await tester.pumpWidget(_app(port, repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('grant-rom-tree')));
    await tester.pumpAndSettle();
    expect(port.picks, 1);
    expect(await repo.romTree(), isNull);
    expect(
      find.text('Needed by most emulators to open the ROM'),
      findsOneWidget,
    );

    port.tree = const RomTree(uri: 'content://tree', path: '/roms');
    await tester.tap(find.byKey(const Key('grant-rom-tree')));
    await tester.pumpAndSettle();
    expect(find.text('Granted: /roms'), findsOneWidget);
    expect((await repo.romTree())!.uri, 'content://tree');
  });

  testWidgets('a tree outside internal storage shows its URI', (tester) async {
    final port = FakeLauncherPort(tree: const RomTree(uri: 'content://sd'));
    await tester.pumpWidget(_app(port, repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('grant-rom-tree')));
    await tester.pumpAndSettle();
    expect(find.text('Granted: content://sd'), findsOneWidget);
  });

  testWidgets('back returns to Settings', (tester) async {
    await tester.pumpWidget(_app(FakeLauncherPort(), repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('back-button')));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
  });
}
