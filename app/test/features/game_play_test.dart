import 'dart:async';

import 'package:droplet/app/input/gamepad.dart';
import 'package:droplet/app/widgets/primary_button.dart';
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:droplet/core/launch/emulator_settings.dart';
import 'package:droplet/core/launch/launch_request.dart';
import 'package:droplet/core/platform/downloader_port.dart';
import 'package:droplet/core/platform/launcher_port.dart';
import 'package:droplet/features/game/game_detail_screen.dart';
import 'package:droplet/features/game/providers.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../fakes/fake_device_index.dart';
import '../fakes/fake_downloader_port.dart';
import '../fakes/fake_launcher_port.dart';
import '../helpers/focus.dart';

GameFileModel _file(String name, FileRole role) => GameFileModel(
  id: 1,
  name: name,
  relativePath: 'x/$name',
  role: role,
  discNumber: null,
  version: '',
  size: 1024,
);

GameDetail _game({
  String system = 'switch',
  String systemName = 'Switch',
  List<GameFileModel>? files,
}) => GameDetail(
  id: 7,
  title: 'Hollow Knight',
  systemCode: system,
  systemName: systemName,
  hasCover: false,
  totalSize: 1024,
  folder: 'Hollow Knight',
  files: files ?? [_file('hk.nsp', FileRole.base)],
);

const _installed = LocalGameState(
  status: InstallStatus.installed,
  updateAvailable: false,
  missing: [],
  presentPaths: ['/roms/switch/Hollow Knight/hk.nsp'],
);

const _none = LocalGameState(
  status: InstallStatus.none,
  updateAvailable: false,
  missing: [],
  presentPaths: [],
);

GoRouter _router() => GoRouter(
  initialLocation: '/game/7',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const Scaffold(body: Text('Home')),
      routes: [
        GoRoute(
          path: 'game/:id',
          builder: (_, s) =>
              GameDetailScreen(gameId: int.parse(s.pathParameters['id']!)),
        ),
      ],
    ),
    GoRoute(
      path: '/settings/emulators',
      builder: (_, __) => const Scaffold(body: Text('Emulators screen')),
    ),
  ],
);

Widget _app({
  required GameDetail game,
  required LocalGameState state,
  required FakeLauncherPort port,
  bool pad = false,
}) => ProviderScope(
  overrides: [
    gameDetailProvider(7).overrideWith((ref) async => game),
    localStateProvider(7).overrideWith((ref) async => state),
    downloaderPortProvider.overrideWithValue(FakeDownloaderPort()),
    launcherPortProvider.overrideWithValue(port),
    storageSettingsProvider.overrideWith(
      (ref) async => StorageSettings('/roms', const {}),
    ),
    deviceIndexProvider.overrideWith(() => FakeDeviceIndex({})),
  ],
  // The shell carries the Start shortcut in the real app.
  child: pad
      ? GamepadShortcuts(
          currentIndex: 0,
          onTab: (_) {},
          child: MaterialApp.router(routerConfig: _router()),
        )
      : MaterialApp.router(routerConfig: _router()),
);

void main() {
  // The focus glow follows Flutter's highlight mode: visible only after a key
  // or pad event. These tests assert on the glow, so they run in that mode.
  setUp(() => FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional);
  tearDown(() => FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.automatic);

  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  testWidgets('installed with an emulator: Play launches it', (tester) async {
    final port = FakeLauncherPort(installed: {'dev.eden.eden_emulator'});
    await tester.pumpWidget(
      _app(game: _game(), state: _installed, port: port),
    );
    await tester.pumpAndSettle();
    expect(find.text('Play'), findsOneWidget);
    await tester.tap(find.byKey(const Key('play-button')));
    await tester.pumpAndSettle();
    final request = port.launched.single;
    expect(request.package, 'dev.eden.eden_emulator');
    expect(request.dataMode, DataMode.provider);
    expect(request.romPath, '/roms/switch/Hollow Knight/hk.nsp');
  });

  testWidgets('Play takes the focus and Start presses it', (tester) async {
    final port = FakeLauncherPort(installed: {'dev.eden.eden_emulator'});
    await tester.pumpWidget(
      _app(game: _game(), state: _installed, port: port, pad: true),
    );
    await tester.pumpAndSettle();
    expect(hasGlow(tester, find.byKey(const Key('play-button'))), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await tester.pumpAndSettle();
    expect(port.launched, hasLength(1));
  });

  testWidgets('Start on an installed game without an emulator does nothing', (
    tester,
  ) async {
    final port = FakeLauncherPort();
    await tester.pumpWidget(
      _app(game: _game(), state: _installed, port: port, pad: true),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await tester.pumpAndSettle();
    expect(port.launched, isEmpty);
  });

  testWidgets('no emulator: the link leads to the settings screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(game: _game(), state: _installed, port: FakeLauncherPort()),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('play-button')), findsNothing);
    await tester.tap(find.byKey(const Key('setup-emulator')));
    await tester.pumpAndSettle();
    expect(find.text('Emulators screen'), findsOneWidget);
  });

  testWidgets('a game that is not installed offers neither', (tester) async {
    final port = FakeLauncherPort(installed: {'dev.eden.eden_emulator'});
    await tester.pumpWidget(_app(game: _game(), state: _none, port: port));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('play-button')), findsNothing);
    expect(find.byKey(const Key('setup-emulator')), findsNothing);
  });

  testWidgets('nothing bootable: no Play even when installed', (tester) async {
    final port = FakeLauncherPort(installed: {'dev.eden.eden_emulator'});
    await tester.pumpWidget(
      _app(
        game: _game(files: [_file('mods/skin.zip', FileRole.mod)]),
        state: _installed,
        port: port,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('play-button')), findsNothing);
    expect(find.byKey(const Key('setup-emulator')), findsNothing);
  });

  testWidgets('an emulator that needs the SAF tree asks for it', (
    tester,
  ) async {
    final port = FakeLauncherPort(installed: {'org.azahar_emu.azahar'});
    await tester.pumpWidget(
      _app(
        game: _game(
          system: 'n3ds',
          systemName: 'Nintendo 3DS',
          files: [_file('g.3ds', FileRole.base)],
        ),
        state: _installed,
        port: port,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('play-button')));
    await tester.pumpAndSettle();
    expect(
      find.text('Grant folder access in Settings → Emulators'),
      findsOneWidget,
    );
    expect(port.launched, isEmpty);
  });

  testWidgets('a granted tree lets the same emulator through', (tester) async {
    final port = FakeLauncherPort(installed: {'org.azahar_emu.azahar'});
    await EmulatorSettingsRepository(
      SharedPreferencesAsync(),
    ).saveRomTree(const RomTree(uri: 'content://tree', path: '/roms'));
    await tester.pumpWidget(
      _app(
        game: _game(
          system: 'n3ds',
          systemName: 'Nintendo 3DS',
          files: [_file('g.3ds', FileRole.base)],
        ),
        state: _installed,
        port: port,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('play-button')));
    await tester.pumpAndSettle();
    expect(port.launched.single.romTreeUri, 'content://tree');
    expect(port.launched.single.dataMode, DataMode.saf);
  });

  testWidgets('a system the catalogue does not cover says so', (tester) async {
    final port = FakeLauncherPort(installed: {'dev.eden.eden_emulator'});
    await tester.pumpWidget(
      _app(
        game: _game(
          system: 'zx81',
          systemName: 'ZX81',
          files: [_file('g.p', FileRole.base)],
        ),
        state: _installed,
        port: port,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No emulator configured'), findsOneWidget);
    // Nothing to set up: the Emulators screen could only repeat it.
    expect(find.byKey(const Key('setup-emulator')), findsNothing);
    expect(find.byKey(const Key('play-button')), findsNothing);
  });

  testWidgets('an exception from the channel lands in the snackbar too', (
    tester,
  ) async {
    final port = FakeLauncherPort(installed: {'dev.eden.eden_emulator'})
      ..launchThrows = PlatformException(code: 'error', message: 'no activity');
    await tester.pumpWidget(
      _app(game: _game(), state: _installed, port: port),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('play-button')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't start Eden: no activity"), findsOneWidget);
  });

  testWidgets('a launch in flight ignores a second tap', (tester) async {
    final port = FakeLauncherPort(installed: {'dev.eden.eden_emulator'})
      ..hold = Completer<void>();
    await tester.pumpWidget(
      _app(game: _game(), state: _installed, port: port),
    );
    await tester.pumpAndSettle();
    final play = find.byKey(const Key('play-button'));
    await tester.tap(play);
    await tester.pump();
    expect(tester.widget<PrimaryButton>(play).busy, isTrue);
    await tester.tap(play);
    await tester.pump();
    port.hold!.complete();
    await tester.pumpAndSettle();
    expect(port.launched, hasLength(1));
    expect(tester.widget<PrimaryButton>(play).busy, isFalse);
  });

  testWidgets('a launch error lands in a snackbar', (tester) async {
    final port = FakeLauncherPort(installed: {'dev.eden.eden_emulator'})
      ..launchResult = 'activity-not-found';
    await tester.pumpWidget(
      _app(game: _game(), state: _installed, port: port),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('play-button')));
    await tester.pumpAndSettle();
    expect(
      find.text("Couldn't start Eden: activity-not-found"),
      findsOneWidget,
    );
  });
}
