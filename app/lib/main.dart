import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/session/providers.dart';

// coverage:ignore-start
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FileDownloader().configureNotification(
    running: const TaskNotification('Pobieram {filename}', '{progress}'),
    complete: const TaskNotification('Gotowe', '{filename}'),
    error: const TaskNotification('Błąd pobierania', '{filename}'),
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
        home: const AppBackground(child: Scaffold()),
      );
    }
    return MaterialApp.router(
      title: 'Droplet',
      theme: buildTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
