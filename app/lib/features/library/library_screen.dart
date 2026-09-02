import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../app/widgets/pulse_box.dart';
import '../../core/api/models.dart';
import '../../core/downloads/download_manager.dart';
import '../downloads/downloads_screen.dart';
import 'providers.dart';
import 'widgets/game_card.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = ref.watch(gamesProvider);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const _SearchField(),
        actions: [
          const _DownloadsAction(),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Ustawienia',
            onPressed: () => context.go('/settings'),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(52),
          child: _SystemBar(),
        ),
      ),
      body: Column(
        children: [
          if (ref.watch(isOfflineProvider)) const _OfflineBanner(),
          Expanded(child: _Grid(games: games)),
        ],
      ),
    );
  }
}

class _Grid extends ConsumerWidget {
  const _Grid({required this.games});

  final AsyncValue<List<GameSummary>> games;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
        onRefresh: () async => ref.invalidate(librarySnapshotProvider),
        child: games.when(
          loading: () => const _LibrarySkeleton(),
          error: (error, _) => _ErrorState(
            message: error.toString(),
            onRetry: () => ref.invalidate(librarySnapshotProvider),
          ),
          data: (list) => list.isEmpty
              ? const _EmptyState()
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 20,
                    childAspectRatio: 0.62,
                  ),
                  itemCount: list.length,
                  itemBuilder: (_, i) => GameCard(game: list[i]),
                ),
        ),
      );
  }
}

/// The library still opens without a server; the banner says so plainly.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: kSurface,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: const Row(
          children: [
            Icon(Icons.cloud_off, size: 16, color: kTextDim),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tryb offline — pokazuję ostatnio pobraną bibliotekę',
                style: TextStyle(color: kTextDim, fontSize: 13),
              ),
            ),
          ],
        ),
      );
}

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _controller,
        onChanged: (value) =>
            ref.read(searchQueryProvider.notifier).update(value),
        style: const TextStyle(color: kText, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Szukaj w bibliotece',
          hintStyle: const TextStyle(color: kTextDim, fontSize: 15),
          prefixIcon: const Icon(Icons.search, color: kTextDim, size: 20),
          filled: true,
          fillColor: kSurface,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
        ),
      );
}

class _SystemBar extends ConsumerWidget {
  const _SystemBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final systems = ref.watch(systemsProvider);
    final selected = ref.watch(selectedSystemProvider);
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _SystemChip(
            label: 'Wszystkie',
            selected: selected == null,
            onTap: () => ref.read(selectedSystemProvider.notifier).select(null),
          ),
          ...systems.maybeWhen(
            data: (list) => list.map(
              (SystemModel s) => _SystemChip(
                label: s.name,
                selected: selected == s.code,
                onTap: () =>
                    ref.read(selectedSystemProvider.notifier).select(s.code),
              ),
            ),
            orElse: () => const <Widget>[],
          ),
        ],
      ),
    );
  }
}

class _SystemChip extends StatelessWidget {
  const _SystemChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? kAccent.withValues(alpha: 0.16) : kSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? kAccent : Colors.transparent,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? kAccent : kTextDim,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 80),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kTextDim),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton(onPressed: onRetry, child: const Text('Ponów')),
          ),
        ],
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(32),
        children: const [
          SizedBox(height: 100),
          Text(
            'Nic tu nie ma',
            textAlign: TextAlign.center,
            style: TextStyle(color: kText, fontSize: 17),
          ),
          SizedBox(height: 8),
          Text(
            'Uruchom skan na serwerze albo zmień filtr.',
            textAlign: TextAlign.center,
            style: TextStyle(color: kTextDim),
          ),
        ],
      );
}


/// Queue shortcut; the badge shows how many games are still downloading.
class _DownloadsAction extends ConsumerWidget {
  const _DownloadsAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref
        .watch(activeDownloadsProvider)
        .where((d) => d.status != GameProgressStatus.complete)
        .length;
    return IconButton(
      tooltip: 'Pobierania',
      onPressed: () => context.go('/downloads'),
      icon: Badge(
        isLabelVisible: active > 0,
        label: Text('$active'),
        backgroundColor: kAccent,
        textColor: kBg,
        child: const Icon(Icons.download_outlined),
      ),
    );
  }
}


/// Six cover-shaped blocks: the grid keeps its rhythm while data loads.
class _LibrarySkeleton extends StatelessWidget {
  const _LibrarySkeleton();

  @override
  Widget build(BuildContext context) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 20,
          childAspectRatio: 0.62,
        ),
        itemCount: 6,
        itemBuilder: (_, __) => const PulseBox(),
      );
}
