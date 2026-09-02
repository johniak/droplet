import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:droplet/core/api/api_client.dart';
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:droplet/core/platform/downloader_port.dart';
import 'package:droplet/core/platform/permissions_port.dart';
import 'package:droplet/core/session/providers.dart';
import 'package:droplet/core/session/session_repository.dart';
import 'package:droplet/features/game/game_detail_screen.dart';
import 'package:droplet/features/game/providers.dart';
import 'package:droplet/features/library/widgets/game_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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
    await tester.tap(find.textContaining('Pobierz'));
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
    await tester.tap(find.textContaining('Pobierz'));
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

  group('install badge', () {
    Future<void> pumpCard(WidgetTester tester, LocalGameState? state) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://nas:8000', token: 't'),
            ),
            if (state != null)
              localStateProvider(1).overrideWith((ref) async => state),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 300,
                child: GameCard(
                  game: GameSummary(
                    id: 1,
                    title: 'Mario',
                    systemCode: 'snes',
                    hasCover: false,
                    totalSize: 1024,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('installed shows a check', (tester) async {
      await pumpCard(
        tester,
        const LocalGameState(
          status: InstallStatus.installed,
          updateAvailable: false,
          missing: [],
          presentPaths: ['/roms/snes/m.sfc'],
        ),
      );
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('an available update shows an arrow', (tester) async {
      await pumpCard(
        tester,
        const LocalGameState(
          status: InstallStatus.installed,
          updateAvailable: true,
          missing: [],
          presentPaths: ['/roms/snes/m.sfc'],
        ),
      );
      expect(find.byIcon(Icons.arrow_circle_down), findsOneWidget);
    });

    testWidgets('a partial install shows a half marker', (tester) async {
      await pumpCard(
        tester,
        const LocalGameState(
          status: InstallStatus.partial,
          updateAvailable: false,
          missing: [_file],
          presentPaths: ['/roms/snes/m.sfc'],
        ),
      );
      expect(find.byIcon(Icons.adjust), findsOneWidget);
    });

    testWidgets('nothing installed shows no badge', (tester) async {
      await pumpCard(tester, _none);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.byIcon(Icons.adjust), findsNothing);
    });
  });

  testWidgets(
    'a GameCard with a cover renders the network image and navigates',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => Scaffold(
              body: SizedBox(
                height: 300,
                child: GameCard(
                  game: const GameSummary(
                    id: 1,
                    title: 'Zelda',
                    systemCode: 'snes',
                    hasCover: true,
                    totalSize: 1024,
                  ),
                ),
              ),
            ),
            routes: [
              GoRoute(
                path: 'game/:id',
                builder: (_, s) =>
                    Scaffold(body: Text('Gra ${s.pathParameters['id']}')),
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://nas:8000', token: 't'),
            ),
            localStateProvider(1).overrideWith((ref) async => _none),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CachedNetworkImage), findsOneWidget);
      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.imageUrl, contains('/api/games/1/cover'));
      expect(image.httpHeaders, containsPair('Authorization', 'Token t'));
      await tester.tap(find.byType(GameCard));
      await tester.pumpAndSettle();
      expect(find.text('Gra 1'), findsOneWidget);
    },
  );

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
    await tester.tap(find.textContaining('Pobierz'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Za mało miejsca'), findsOneWidget);
    expect(port.enqueued, isEmpty);
  });
}
