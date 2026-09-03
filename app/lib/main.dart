import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/session/providers.dart';

// coverage:ignore-start
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FileDownloader().configureNotification(
    running: const TaskNotification('Downloading {filename}', '{progress}'),
    complete: const TaskNotification('Done', '{filename}'),
    error: const TaskNotification('Download failed', '{filename}'),
    progressBar: true,
  );
  runApp(const ProviderScope(child: DropletApp()));
}
// coverage:ignore-end

class DropletApp extends ConsumerWidget {
  const DropletApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Until the stored session is read, '/' would build without an API client.
    if (ref.watch(sessionProvider).isLoading) {
      return MaterialApp(
        theme: buildTheme(),
        builder: _lightStatusBar,
        home: const AppBackground(child: Scaffold()),
      );
    }
    return MaterialApp.router(
      title: 'Droplet',
      theme: buildTheme(),
      builder: _lightStatusBar,
      routerConfig: ref.watch(routerProvider),
    );
  }

  /// Light status bar icons for the whole app — not just for the shell with
  /// the bottom navigation: login and the game detail sit outside it, and the
  /// background is dark everywhere.
  static Widget _lightStatusBar(BuildContext context, Widget? child) =>
      AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: child!,
      );
}
