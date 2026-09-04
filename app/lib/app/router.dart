import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/session/providers.dart';
import '../features/auth/login_screen.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/game/game_detail_screen.dart';
import '../features/home/home_screen.dart';
import '../features/settings/emulators_screen.dart';
import '../features/settings/folders_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/system/system_screen.dart';
import 'branch_host.dart';
import 'shell.dart';
import 'theme.dart';

export 'shell.dart' show hidesNavBar;

GoRoute _gameRoute() => GoRoute(
  path: 'game/:id',
  builder: (_, s) =>
      GameDetailScreen(gameId: int.parse(s.pathParameters['id']!)),
);

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
      GoRoute(
        path: '/login',
        builder: (_, __) => const AppBackground(child: LoginScreen()),
      ),
      StatefulShellRoute(
        builder: (context, state, shell) =>
            AppShell(shell: shell, hideBar: hidesNavBar(state.uri.path)),
        navigatorContainerBuilder: (context, shell, children) =>
            BranchHost(index: shell.currentIndex, children: children),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, __) => const HomeScreen(),
                routes: [
                  _gameRoute(),
                  GoRoute(
                    path: 'system/:code',
                    builder: (_, s) =>
                        SystemScreen(code: s.pathParameters['code']!),
                    routes: [_gameRoute()],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/downloads',
                builder: (_, __) => const DownloadsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, __) => const SettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'folders',
                    builder: (_, __) => const FoldersScreen(),
                  ),
                  GoRoute(
                    path: 'emulators',
                    builder: (_, __) => const EmulatorsScreen(),
                  ),
                  // The System files card links here so a tap stays on the
                  // Settings tab instead of jumping to the library branch.
                  _gameRoute(),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
