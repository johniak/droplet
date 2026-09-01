import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/session/providers.dart';

// coverage:ignore-start
void main() => runApp(const ProviderScope(child: DropletApp()));
// coverage:ignore-end

class DropletApp extends ConsumerWidget {
  const DropletApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Until the stored session is read, '/' would build without an API client.
    if (ref.watch(sessionProvider).isLoading) {
      return MaterialApp(
        theme: buildTheme(),
        home: const Scaffold(backgroundColor: kBg),
      );
    }
    return MaterialApp.router(
      title: 'Droplet',
      theme: buildTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
