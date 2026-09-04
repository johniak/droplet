import 'dart:async';
import 'dart:io';

import 'package:droplet/app/input/gamepad.dart';
import 'package:droplet/app/widgets/primary_button.dart';
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:droplet/core/platform/downloader_port.dart';
import 'package:droplet/core/platform/permissions_port.dart';
import 'package:droplet/core/session/providers.dart';
import 'package:droplet/core/session/session_repository.dart';
import 'package:droplet/features/game/game_detail_screen.dart';
import 'package:droplet/features/game/providers.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_downloader_port.dart';
import '../fakes/fake_permissions_port.dart';
import '../helpers/focus.dart';

const _file = GameFileModel(
  id: 1,
  name: 'm.sfc',
  relativePath: 'snes/m.sfc',
  role: FileRole.base,
  discNumber: null,
  version: '',
  size: 1024,
);
const _game = GameDetail(
  id: 7,
  title: 'Mario',
  systemCode: 'snes',
  systemName: 'SNES',
  hasCover: false,
  totalSize: 1024,
  folder: 'Mario',
  files: [_file],
);
const _none = LocalGameState(
  status: InstallStatus.none,
  updateAvailable: false,
  missing: [_file],
  presentPaths: [],
);

class _Session extends SessionController {
  @override
  Future<Session?> build() async =>
      const Session(serverUrl: 'http://nas:8000', token: 't');
}

/// The detail screen under the shell's gamepad shortcuts, so Start reaches
/// the screen's own PrimaryActionIntent handler.
Widget _padApp(FakeDownloaderPort port, LocalGameState state) => ProviderScope(
  overrides: [
    sessionProvider.overrideWith(_Session.new),
    gameDetailProvider(7).overrideWith((ref) async => _game),
    localStateProvider(7).overrideWith((ref) async => state),
    storageSettingsProvider.overrideWith(
      (ref) async => StorageSettings('/roms', const {}),
    ),
    downloaderPortProvider.overrideWithValue(port),
    permissionsPortProvider.overrideWithValue(
      FakePermissionsPort(granted: true),
    ),
  ],
  child: MaterialApp(
    home: GamepadShortcuts(
      currentIndex: 0,
      onTab: (_) {},
      child: const GameDetailScreen(gameId: 7),
    ),
  ),
);

void main() {
  // The focus glow follows Flutter's highlight mode: visible only after a key
  // or pad event. These tests assert on the glow, so they run in that mode.
  setUp(() => FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional);
  tearDown(() => FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.automatic);

  testWidgets('Download takes the focus and Start presses it', (tester) async {
    final port = FakeDownloaderPort();
    await tester.pumpWidget(_padApp(port, _none));
    await tester.pumpAndSettle();
    expect(find.textContaining('Download ·'), findsOneWidget);
    expect(hasGlow(tester, find.byType(PrimaryButton)), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await tester.pumpAndSettle();
    expect(port.enqueued.single.url, 'http://nas:8000/api/files/1/download');
  });

  testWidgets('Start does nothing when there is nothing left to fetch', (
    tester,
  ) async {
    final port = FakeDownloaderPort();
    await tester.pumpWidget(
      _padApp(
        port,
        const LocalGameState(
          status: InstallStatus.partial,
          updateAvailable: false,
          missing: [],
          presentPaths: ['/roms/snes/Mario/m.sfc'],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await tester.pumpAndSettle();
    expect(port.enqueued, isEmpty);
  });

  testWidgets('tapping download enqueues the selected files', (tester) async {
    final port = FakeDownloaderPort();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(_Session.new),
          gameDetailProvider(7).overrideWith((ref) async => _game),
          localStateProvider(7).overrideWith((ref) async => _none),
          storageSettingsProvider.overrideWith(
            (ref) async => StorageSettings('/roms', const {}),
          ),
          downloaderPortProvider.overrideWithValue(port),
          permissionsPortProvider.overrideWithValue(
            FakePermissionsPort(granted: true),
          ),
        ],
        child: const MaterialApp(home: GameDetailScreen(gameId: 7)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Download ·'));
    await tester.pumpAndSettle();
    expect(port.enqueued.single.url, 'http://nas:8000/api/files/1/download');
  });

  testWidgets('a denied permission explains itself in a snackbar', (
    tester,
  ) async {
    final port = FakeDownloaderPort();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(_Session.new),
          gameDetailProvider(7).overrideWith((ref) async => _game),
          localStateProvider(7).overrideWith((ref) async => _none),
          storageSettingsProvider.overrideWith(
            (ref) async => StorageSettings('/roms', const {}),
          ),
          downloaderPortProvider.overrideWithValue(port),
          permissionsPortProvider.overrideWithValue(
            FakePermissionsPort(granted: false),
          ),
        ],
        child: const MaterialApp(home: GameDetailScreen(gameId: 7)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Download ·'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('grant the permission'), findsOneWidget);
    expect(port.enqueued, isEmpty);
  });

  testWidgets('while the local state loads the button waits', (tester) async {
    final completer = Completer<LocalGameState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameDetailProvider(7).overrideWith((ref) async => _game),
          localStateProvider(7).overrideWith((ref) => completer.future),
        ],
        child: const MaterialApp(home: GameDetailScreen(gameId: 7)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Checking files...'), findsOneWidget);
    completer.complete(_none);
    await tester.pumpAndSettle();
  });

  testWidgets('a failing local state is reported on the game screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameDetailProvider(7).overrideWith((ref) async => _game),
          localStateProvider(7)
              .overrideWith((ref) async => throw StateError('disk')),
        ],
        child: const MaterialApp(home: GameDetailScreen(gameId: 7)),
      ),
    );
    await tester.pumpAndSettle();
    // Since M6 the raw exception is replaced by a human message.
    expect(find.text('Something went wrong'), findsOneWidget);
  });

  test('localStateProvider diffs the manifest against the disk', () async {
    final dir = Directory.systemTemp.createTempSync();
    addTearDown(() => dir.deleteSync(recursive: true));
    Directory('${dir.path}/snes/Mario').createSync(recursive: true);
    File('${dir.path}/snes/Mario/m.sfc').writeAsBytesSync(List.filled(1024, 0));
    final container = ProviderContainer(
      overrides: [
        librarySnapshotProvider.overrideWith(
          (ref) async => const LibrarySnapshot(
            systems: [
              SystemModel(id: 1, code: 'snes', name: 'SNES', gameCount: 1),
            ],
            games: [],
            manifest: [
              ManifestEntry(
                gameId: 7,
                systemCode: 'snes',
                folder: 'Mario',
                files: [_file],
              ),
            ],
            fromCache: false,
            previousIds: {},
          ),
        ),
        storageSettingsProvider.overrideWith(
          (ref) async => StorageSettings(dir.path, const {}),
        ),
      ],
    );
    addTearDown(container.dispose);
    final state = await container.read(localStateProvider(7).future);
    expect(state.status, InstallStatus.installed);
  });

  testWidgets('not enough space is explained in a snackbar', (tester) async {
    final port = FakeDownloaderPort()..free = 1;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(_Session.new),
          gameDetailProvider(7).overrideWith((ref) async => _game),
          localStateProvider(7).overrideWith((ref) async => _none),
          storageSettingsProvider.overrideWith(
            (ref) async => StorageSettings('/roms', const {}),
          ),
          downloaderPortProvider.overrideWithValue(port),
          permissionsPortProvider.overrideWithValue(
            FakePermissionsPort(granted: true),
          ),
        ],
        child: const MaterialApp(home: GameDetailScreen(gameId: 7)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Download ·'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Not enough space'), findsOneWidget);
    expect(port.enqueued, isEmpty);
  });
}
