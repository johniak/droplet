import 'package:droplet/core/session/providers.dart';
import 'package:droplet/core/session/session_repository.dart';
import 'package:droplet/features/auth/login_screen.dart';
import 'package:droplet/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _app(KeyValueStore store) => ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(SessionRepository(store)),
      ],
      child: const DropletApp(),
    );

Future<MemoryKeyValueStore> _signedIn() async {
  final store = MemoryKeyValueStore();
  await SessionRepository(store)
      .save(const Session(serverUrl: 'http://nas:8000', token: 't'));
  return store;
}

void main() {
  testWidgets('no session -> login screen', (tester) async {
    await tester.pumpWidget(_app(MemoryKeyValueStore()));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('session -> library', (tester) async {
    await tester.pumpWidget(_app(await _signedIn()));
    await tester.pumpAndSettle();
    expect(find.text('Biblioteka'), findsOneWidget);
  });

  testWidgets('nested routes render below the library', (tester) async {
    await tester.pumpWidget(_app(await _signedIn()));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('Biblioteka'));

    context.go('/game/7');
    await tester.pumpAndSettle();
    expect(find.text('Gra 7'), findsOneWidget);

    context.go('/settings');
    await tester.pumpAndSettle();
    expect(find.text('Ustawienia'), findsOneWidget);
  });

  testWidgets('signing in redirects away from login', (tester) async {
    final store = MemoryKeyValueStore();
    final repo = SessionRepository(store);
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const DropletApp();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await repo.save(const Session(serverUrl: 'http://nas:8000', token: 't'));
    container.read(sessionProvider.notifier).state =
        const AsyncData(Session(serverUrl: 'http://nas:8000', token: 't'));
    await tester.pumpAndSettle();
    expect(find.text('Biblioteka'), findsOneWidget);
  });
}
