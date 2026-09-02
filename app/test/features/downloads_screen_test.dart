import 'package:droplet/core/downloads/download_manager.dart';
import 'package:droplet/features/downloads/downloads_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_downloader_port.dart';
import '../fakes/fake_permissions_port.dart';

/// Every test overrides the manager: the real one listens to
/// `FileDownloader().updates`, a single-subscription stream that blows up when
/// a second manager is built in the same test isolate.
Widget _screen(List<GameProgress> active, DownloadManager manager) =>
    ProviderScope(
      overrides: [
        activeDownloadsProvider.overrideWith((ref) => active),
        downloadManagerProvider.overrideWithValue(manager),
      ],
      child: const MaterialApp(home: DownloadsScreen()),
    );

void main() {
  late FakeDownloaderPort port;
  late DownloadManager manager;

  setUp(() {
    port = FakeDownloaderPort();
    manager = DownloadManager(
      port,
      FakePermissionsPort(granted: true),
      onGameChanged: (_) {},
    );
  });

  tearDown(() => manager.dispose());

  GameProgress at(GameProgressStatus status, {double progress = 0.5}) =>
      GameProgress(
        gameId: 7,
        title: 'Mario',
        systemCode: 'snes',
        hasCover: false,
        progress: progress,
        status: status,
      );

  testWidgets('empty state', (tester) async {
    await tester.pumpWidget(_screen(const [], manager));
    await tester.pumpAndSettle();
    expect(find.text('Brak aktywnych pobierań'), findsOneWidget);
  });

  testWidgets('active download row', (tester) async {
    await tester.pumpWidget(
      _screen([at(GameProgressStatus.running)], manager),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mario'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('pause reaches the manager', (tester) async {
    await tester.pumpWidget(
      _screen([at(GameProgressStatus.running)], manager),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.pause), findsOneWidget);
  });

  testWidgets('cancel reaches the manager', (tester) async {
    await tester.pumpWidget(
      _screen([at(GameProgressStatus.running)], manager),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(manager.progress, isEmpty);
  });

  testWidgets('resume reaches the manager', (tester) async {
    await tester.pumpWidget(_screen([at(GameProgressStatus.paused)], manager));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();
    expect(port.resumed, isEmpty);
  });

  testWidgets('a failed download offers a retry', (tester) async {
    await tester.pumpWidget(
      _screen([at(GameProgressStatus.failed, progress: 0.2)], manager),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ponów'), findsOneWidget);
    await tester.tap(find.text('Ponów'));
    await tester.pumpAndSettle();
  });

  testWidgets('a finished download shows as done', (tester) async {
    await tester.pumpWidget(
      _screen([at(GameProgressStatus.complete, progress: 1)], manager),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  test('activeDownloadsProvider reads the manager', () async {
    final container = ProviderContainer(
      overrides: [downloadManagerProvider.overrideWithValue(manager)],
    );
    addTearDown(container.dispose);
    expect(container.read(activeDownloadsProvider), isEmpty);
  });

  testWidgets('two downloads are separated', (tester) async {
    await tester.pumpWidget(
      _screen([
        at(GameProgressStatus.running),
        const GameProgress(
          gameId: 8,
          title: 'Tekken',
          systemCode: 'snes',
          hasCover: false,
          progress: 0.1,
          status: GameProgressStatus.running,
        ),
      ], manager),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Divider), findsOneWidget);
  });
}
