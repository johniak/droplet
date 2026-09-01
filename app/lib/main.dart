import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';

// coverage:ignore-start
void main() => runApp(const ProviderScope(child: DropletApp()));
// coverage:ignore-end

class DropletApp extends StatelessWidget {
  const DropletApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Droplet',
        theme: buildTheme(),
        routerConfig: buildRouter(),
      );
}
