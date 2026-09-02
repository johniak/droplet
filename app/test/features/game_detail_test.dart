import 'package:droplet/core/api/api_client.dart';
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/core/session/providers.dart';
import 'package:droplet/core/format.dart';
import 'package:droplet/features/game/game_detail_screen.dart';
import 'package:droplet/features/game/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _detail = GameDetail(
  id: 7,
  title: 'Hollow Knight',
  systemCode: 'switch',
  systemName: 'Switch',
  hasCover: false,
  totalSize: 3,
  files: [
    GameFileModel(
      id: 1,
      name: 'hk.nsp',
      relativePath: 'switch/hk.nsp',
      role: FileRole.base,
      discNumber: null,
      version: '',
      size: 1,
    ),
    GameFileModel(
      id: 2,
      name: 'upd.nsp',
      relativePath: 'switch/upd.nsp',
      role: FileRole.update,
      discNumber: null,
      version: 'v196608',
      size: 2,
    ),
  ],
);

const _notInstalled = LocalGameState(
  status: InstallStatus.none,
  updateAvailable: false,
  missing: [],
  presentPaths: [],
);

Widget _screen(GameDetail detail) => ProviderScope(
      overrides: [
        gameDetailProvider(7).overrideWith((ref) async => detail),
        localStateProvider(7).overrideWith((ref) async => _notInstalled),
      ],
      child: const MaterialApp(home: GameDetailScreen(gameId: 7)),
    );

void main() {
  test('formatBytes', () {
    expect(formatBytes(500), '500 B');
    expect(formatBytes(2048), '2.0 KB');
    expect(formatBytes(1500000000), '1.4 GB');
  });

  testWidgets('shows role sections', (tester) async {
    await tester.pumpWidget(_screen(_detail));
    await tester.pumpAndSettle();
    expect(find.text('Hollow Knight'), findsWidgets);
    expect(find.text('Aktualizacja'), findsOneWidget);
    // The manifest sits below the fold once every row carries a checkbox.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.textContaining('v196608'), findsOneWidget);
  });

  testWidgets('discs and support files get their own labels', (tester) async {
    const multiDisc = GameDetail(
      id: 7,
      title: 'Final Fantasy VII',
      systemCode: 'psx',
      systemName: 'PlayStation',
      hasCover: false,
      totalSize: 30,
      files: [
        GameFileModel(
          id: 1,
          name: 'ff7-d1.cue',
          relativePath: 'psx/ff7-d1.cue',
          role: FileRole.disc,
          discNumber: 1,
          version: '',
          size: 10,
        ),
        GameFileModel(
          id: 2,
          name: 'ff7-d1.bin',
          relativePath: 'psx/ff7-d1.bin',
          role: FileRole.support,
          discNumber: null,
          version: '',
          size: 20,
        ),
      ],
    );
    await tester.pumpWidget(_screen(multiDisc));
    await tester.pumpAndSettle();
    expect(find.text('Płyta 1'), findsOneWidget);
    expect(find.text('Pozostałe'), findsOneWidget);
  });

  testWidgets('an error shows a retry action', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameDetailProvider(7)
              .overrideWith((ref) async => throw StateError('x')),
          localStateProvider(7).overrideWith((ref) async => _notInstalled),
        ],
        child: const MaterialApp(home: GameDetailScreen(gameId: 7)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ponów'), findsOneWidget);
    await tester.tap(find.text('Ponów'));
    await tester.pumpAndSettle();
    expect(find.text('Ponów'), findsOneWidget);
  });

  testWidgets('a game with a cover uses the full-size boxart', (tester) async {
    const withCover = GameDetail(
      id: 7,
      title: 'Hollow Knight',
      systemCode: 'switch',
      systemName: 'Switch',
      hasCover: true,
      totalSize: 3,
      files: [],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameDetailProvider(7).overrideWith((ref) async => withCover),
          localStateProvider(7).overrideWith((ref) async => _notInstalled),
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://nas:8000', token: 't'),
          ),
        ],
        child: const MaterialApp(home: GameDetailScreen(gameId: 7)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(GameDetailScreen), findsOneWidget);
  });

  test('gameDetailProvider reads the detail endpoint', () async {
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(_FakeClient())],
    );
    addTearDown(container.dispose);
    final game = await container.read(gameDetailProvider(7).future);
    expect(game.title, 'Hollow Knight');
  });
}

class _FakeClient extends ApiClient {
  _FakeClient() : super(baseUrl: 'http://nas:8000', token: 't');

  @override
  Future<GameDetail> fetchGame(int id) async => _detail;
}
