import 'dart:async';
import 'dart:io';

import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:droplet/core/platform/downloader_port.dart';
import 'package:droplet/core/platform/permissions_port.dart';
import 'package:droplet/core/session/providers.dart';
import 'package:droplet/core/session/session_repository.dart';
import 'package:droplet/features/game/game_detail_screen.dart';
import 'package:droplet/features/game/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_downloader_port.dart';
import '../fakes/fake_permissions_port.dart';

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

void main() {
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
    await tester.tap(find.textContaining('Pobierz ·'));
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
    await tester.tap(find.textContaining('Pobierz ·'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('przyznaj uprawnienie'), findsOneWidget);
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
    expect(find.text('Sprawdzam pliki...'), findsOneWidget);
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
              .overrideWith((ref) async => throw StateError('dysk')),
        ],
        child: const MaterialApp(home: GameDetailScreen(gameId: 7)),
      ),
    );
    await tester.pumpAndSettle();
    // Since M6 the raw exception is replaced by a human message.
    expect(find.text('Coś poszło nie tak'), findsOneWidget);
  });

  test('localStateProvider diffs the manifest against the disk', () async {
    final dir = Directory.systemTemp.createTempSync();
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/m.sfc').writeAsBytesSync(List.filled(1024, 0));
    final container = ProviderContainer(
      overrides: [
        gameDetailProvider(7).overrideWith((ref) async => _game),
        storageSettingsProvider.overrideWith(
          (ref) async => StorageSettings(dir.parent.path, {
            'snes': dir.uri.pathSegments[dir.uri.pathSegments.length - 2],
          }),
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
    await tester.tap(find.textContaining('Pobierz ·'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Za mało miejsca'), findsOneWidget);
    expect(port.enqueued, isEmpty);
  });
}
