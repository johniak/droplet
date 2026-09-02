import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/session/providers.dart';
import '../features/auth/login_screen.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/game/game_detail_screen.dart';
import '../features/library/library_screen.dart';
import '../features/settings/folders_screen.dart';
import '../features/settings/settings_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(sessionProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = ref.read(sessionProvider).value != null;
      final onLogin = state.matchedLocation == '/login';
      if (!loggedIn && !onLogin) return '/login';
      if (loggedIn && onLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
        path: '/',
        builder: (_, __) => const LibraryScreen(),
        routes: [
          // Nested: go('/game/7') builds the stack [/, /game/7], so the
          // system back button returns to the library instead of exiting.
          GoRoute(
            path: 'game/:id',
            builder: (_, s) => GameDetailScreen(
              gameId: int.parse(s.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: 'downloads',
            builder: (_, __) => const DownloadsScreen(),
          ),
          GoRoute(
            path: 'settings',
            builder: (_, __) => const SettingsScreen(),
            routes: [
              GoRoute(
                path: 'folders',
                builder: (_, __) => const FoldersScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
