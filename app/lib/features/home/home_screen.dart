import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/layout.dart';
import '../../app/tokens.dart';
import '../../app/widgets/primary_button.dart';
import '../../app/widgets/pulse_box.dart';
import '../../core/errors.dart';
import '../library/providers.dart';
import '../library/widgets/games_grid.dart';
import '../library/widgets/search_field.dart';
import '../library/widgets/shelf.dart';
import '../library/widgets/sort_menu.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Latched on snapshot identity, not on a bool flag: every library refresh
  /// is a new object, so new games get announced again, while repeated
  /// rebuilds of the same snapshot announce only once.
  LibrarySnapshot? _lastAnnounced;

  /// Once per snapshot: what the refresh brought in.
  void _announceNewGames(LibrarySnapshot snapshot) {
    if (identical(snapshot, _lastAnnounced)) return;
    _lastAnnounced = snapshot;
    final count = newGameCount(snapshot.previousIds, [
      for (final g in snapshot.games) g.id,
    ]);
    if (count == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 1
                ? 'New in library: 1 game'
                : 'New in library: $count games',
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(librarySnapshotProvider);
    if (snapshot.hasValue) _announceNewGames(snapshot.requireValue);
    final query = ref.watch(searchQueryProvider).trim();
    final search = SearchField(
      hint: 'Search the library',
      onChanged: (v) => ref.read(searchQueryProvider.notifier).update(v),
    );
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = isWideWidth(constraints.maxWidth);
            return Column(
              children: [
                _Header(search: wide ? search : null),
                if (!wide)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: search,
                  ),
                if (ref.watch(isOfflineProvider)) const _OfflinePill(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async =>
                        ref.invalidate(librarySnapshotProvider),
                    child: snapshot.when(
                      loading: () => const HomeSkeleton(),
                      error: (e, _) => _Message(
                        title: humanizeError(e),
                        action: 'Retry',
                        onAction: () => ref.invalidate(librarySnapshotProvider),
                      ),
                      data: (s) => s.games.isEmpty
                          ? const _Message(
                              title: 'Nothing here yet',
                              subtitle: 'Run a scan on the server.',
                            )
                          : query.isEmpty
                          ? const _Shelves()
                          : const _Results(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.search});

  /// Set in the wide layout: the field sits between the title and the sort
  /// button instead of taking a row of its own.
  final Widget? search;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 16, 8),
    child: Row(
      children: [
        const Expanded(
          child: Text(
            'Droplet',
            style: TextStyle(
              color: kText,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
        ),
        if (search case final field?) ...[
          SizedBox(width: kInlineSearchWidth, child: field),
          const SizedBox(width: 12),
        ],
        const SortMenu(),
      ],
    ),
  );
}

class _OfflinePill extends StatelessWidget {
  const _OfflinePill();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: kGlass,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: kGlassBorder),
    ),
    child: const Row(
      children: [
        Icon(Icons.cloud_off, size: 16, color: kTextDim),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Offline — showing the last synced library',
            style: TextStyle(color: kTextDim, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _Shelves extends ConsumerWidget {
  const _Shelves();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shelves = ref.watch(homeShelvesProvider).value;
    if (shelves == null) return const HomeSkeleton();
    return ListView(
      padding: EdgeInsets.only(bottom: listBottomPad(context)),
      // Stable keys: the "On device" shelf appears only once the badges
      // resolve local state, so without them inserting it mid-list would shift
      // the state (scroll position) of the system shelves by one slot.
      children: [
        Shelf(
          key: const ValueKey('shelf-recent'),
          title: 'Recently added',
          games: shelves.recent,
          cardWidth: 120,
        ),
        if (shelves.installed.isNotEmpty)
          Shelf(
            key: const ValueKey('shelf-installed'),
            title: 'On device',
            games: shelves.installed,
          ),
        for (final shelf in shelves.systems)
          if (shelf.games.isNotEmpty)
            Shelf(
              key: ValueKey('shelf-${shelf.system.code}'),
              title: shelf.system.name,
              trailing: '${shelf.games.length} ›',
              games: shelf.games,
              onSeeAll: () => context.go('/system/${shelf.system.code}'),
            ),
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = ref.watch(gamesProvider).value ?? const [];
    if (games.isEmpty) {
      return const _Message(
        title: 'No results',
        subtitle: 'Try a different title.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Text(
            'Results · ${games.length}',
            style: const TextStyle(
              color: kText,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: GamesGrid(games: games)),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    this.subtitle,
    this.action,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(32),
    children: [
      const SizedBox(height: 80),
      Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(color: kText, fontSize: 17),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 8),
        Text(
          subtitle!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: kTextDim),
        ),
      ],
      if (action != null) ...[
        const SizedBox(height: 20),
        Center(
          child: SizedBox(
            width: 160,
            child: PrimaryButton(label: action!, onPressed: onAction),
          ),
        ),
      ],
    ],
  );
}

/// Three shelves of pulsing blocks — the layout stands before data lands.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(16, 18, 0, listBottomPad(context)),
    children: [
      for (var s = 0; s < 3; s++) ...[
        const PulseBox(height: 18, width: 140),
        const SizedBox(height: 10),
        SizedBox(
          height: 154,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.only(right: 16),
            children: [
              for (var i = 0; i < 4; i++)
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: PulseBox(width: 96, height: 128),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    ],
  );
}
