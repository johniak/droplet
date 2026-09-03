import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:droplet/features/settings/folders_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const systems = [
  SystemModel(id: 1, code: 'snes', name: 'SNES', gameCount: 1),
];

GoRouter _router() => GoRouter(
      initialLocation: '/settings/folders',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (_, __) => const Scaffold(body: Text('Settings')),
          routes: [
            GoRoute(
              path: 'folders',
              builder: (_, __) => const FoldersScreen(),
            ),
          ],
        ),
      ],
    );

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('edits per-system dirs and goes back', (tester) async {
    final repo = StorageSettingsRepository(SharedPreferencesAsync());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageSettingsRepositoryProvider.overrideWithValue(repo),
          systemsProvider.overrideWith((ref) async => systems),
        ],
        child: MaterialApp.router(routerConfig: _router()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Folders per system'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('system-dir-snes')), 'SNES');
    await tester.pumpAndSettle();
    expect((await repo.load()).systemDirs['snes'], 'SNES');
    await tester.tap(find.byKey(const Key('back-button')));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('a separator or .. in the field never reaches the settings', (
    tester,
  ) async {
    final repo = StorageSettingsRepository(SharedPreferencesAsync());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageSettingsRepositoryProvider.overrideWithValue(repo),
          systemsProvider.overrideWith((ref) async => systems),
        ],
        child: MaterialApp.router(routerConfig: _router()),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('system-dir-snes'));
    await tester.enterText(field, 'SNES');
    await tester.pumpAndSettle();
    // The field saves character by character, so ".." and a separator must
    // simply be dropped — otherwise the system folder could escape the ROM tree.
    await tester.enterText(field, '..');
    await tester.pumpAndSettle();
    expect((await repo.load()).systemDirs['snes'], 'SNES');
    await tester.enterText(field, 'a/b');
    await tester.pumpAndSettle();
    expect((await repo.load()).systemDirs['snes'], 'SNES');
    // An empty field means no override, not a folder with an empty name.
    await tester.enterText(field, '');
    await tester.pumpAndSettle();
    expect((await repo.load()).systemDirs.containsKey('snes'), isFalse);
  });

  testWidgets('saving a folder invalidates storageSettingsProvider', (
    tester,
  ) async {
    final repo = StorageSettingsRepository(SharedPreferencesAsync());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageSettingsRepositoryProvider.overrideWithValue(repo),
          systemsProvider.overrideWith((ref) async => systems),
        ],
        child: MaterialApp.router(routerConfig: _router()),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FoldersScreen)),
    );
    await tester.enterText(find.byKey(const Key('system-dir-snes')), 'SNES');
    await tester.pumpAndSettle();
    final settings = await container.read(storageSettingsProvider.future);
    expect(settings.systemDirs['snes'], 'SNES');
  });
}
