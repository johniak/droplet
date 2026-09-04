import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/downloads/providers.dart';
import 'input/gamepad.dart';
import 'theme.dart';
import 'widgets/glass_bar.dart';

bool hidesNavBar(String path) => path.contains('/game/');

/// Background and bottom navigation for the three branches (the status bar is
/// set globally by `DropletApp`).
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell, required this.hideBar});

  final StatefulNavigationShell shell;
  final bool hideBar;

  void _goTab(int i) =>
      shell.goBranch(i, initialLocation: i == shell.currentIndex);

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppBackground(
    // Above the whole Scaffold, bar included: the shortcuts have to fire
    // wherever the focus happens to sit, and the game screen lives under the
    // shell too.
    child: GamepadShortcuts(
      currentIndex: shell.currentIndex,
      onTab: _goTab,
      child: Scaffold(
        extendBody: true,
        body: shell,
        bottomNavigationBar: hideBar
            ? null
            : GlassBar(
                currentIndex: shell.currentIndex,
                badge: ref.watch(activeCountProvider),
                onTap: _goTab,
              ),
      ),
    ),
  );
}
