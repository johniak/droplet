import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/tokens.dart';
import '../providers.dart';

/// Sortowanie za jedną ikoną — bibliotekę przegląda się częściej, niż sortuje.
class SortMenu extends ConsumerWidget {
  const SortMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<LibrarySort>(
        tooltip: 'Sortowanie',
        initialValue: ref.watch(sortProvider),
        onSelected: (v) => ref.read(sortProvider.notifier).select(v),
        itemBuilder: (_) => const [
          PopupMenuItem(value: LibrarySort.title, child: Text('Alfabetycznie')),
          PopupMenuItem(
            value: LibrarySort.recentlyAdded,
            child: Text('Ostatnio dodane'),
          ),
        ],
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
            border: Border.all(color: kGlassBorder),
          ),
          child: const Icon(Icons.sort, size: 20, color: kText),
        ),
      );
}
