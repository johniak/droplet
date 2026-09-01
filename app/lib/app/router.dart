import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

GoRouter buildRouter() => GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const _Stub('Droplet')),
        GoRoute(
          path: '/',
          builder: (_, __) => const _Stub('Biblioteka'),
          routes: [
            // Nested: go('/game/7') builds the stack [/, /game/7], so the
            // system back button returns to the library instead of exiting.
            GoRoute(
              path: 'game/:id',
              builder: (_, s) => _Stub('Gra ${s.pathParameters['id']}'),
            ),
            GoRoute(
              path: 'settings',
              builder: (_, __) => const _Stub('Ustawienia'),
            ),
          ],
        ),
      ],
    );

class _Stub extends StatelessWidget {
  const _Stub(this.title);
  final String title;

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text(title)));
}
