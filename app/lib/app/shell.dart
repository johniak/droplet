import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/downloads/providers.dart';
import 'theme.dart';
import 'widgets/glass_bar.dart';

bool hidesNavBar(String path) => path.contains('/game/');

/// Background and bottom navigation for the three branches (the status bar is
/// set globally by `DropletApp`).
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell, required this.hideBar});

  final StatefulNavigationShell shell;
  final bool hideBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppBackground(
    child: Scaffold(
      extendBody: true,
      body: shell,
      bottomNavigationBar: hideBar
          ? null
          : GlassBar(
              currentIndex: shell.currentIndex,
              badge: ref.watch(activeCountProvider),
              onTap: (i) =>
                  shell.goBranch(i, initialLocation: i == shell.currentIndex),
            ),
    ),
  );
}
