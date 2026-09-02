import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  var _announcedNew = false;

  /// Raz na snapshot: co przyniosło odświeżenie.
  void _announceNewGames(LibrarySnapshot snapshot) {
    if (_announcedNew) return;
    _announcedNew = true;
    final count = newGameCount(
      snapshot.previousIds,
      [for (final g in snapshot.games) g.id],
    );
    if (count == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nowe w bibliotece: $count gier')),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(librarySnapshotProvider);
    if (snapshot.hasValue) _announceNewGames(snapshot.requireValue);
    final query = ref.watch(searchQueryProvider).trim();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _Header(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: SearchField(
                hint: 'Szukaj w bibliotece',
                onChanged: (v) =>
                    ref.read(searchQueryProvider.notifier).update(v),
              ),
            ),
            if (ref.watch(isOfflineProvider)) const _OfflinePill(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => ref.invalidate(librarySnapshotProvider),
                child: snapshot.when(
                  loading: () => const HomeSkeleton(),
                  error: (e, _) => _Message(
                    title: humanizeError(e),
                    action: 'Ponów',
                    onAction: () => ref.invalidate(librarySnapshotProvider),
                  ),
                  data: (s) => s.games.isEmpty
                      ? const _Message(
                          title: 'Nic tu nie ma',
                          subtitle: 'Uruchom skan na serwerze.',
                        )
                      : query.isEmpty
                          ? const _Shelves()
                          : const _Results(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.fromLTRB(20, 10, 16, 8),
        child: Row(
          children: [
            Expanded(
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
            SortMenu(),
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
                'Tryb offline — pokazuję ostatnio pobraną bibliotekę',
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
      padding: const EdgeInsets.only(bottom: kListBottomPad),
      children: [
        Shelf(title: 'Ostatnio dodane', games: shelves.recent, cardWidth: 120),
        if (shelves.installed.isNotEmpty)
          Shelf(title: 'Na urządzeniu', games: shelves.installed),
        for (final shelf in shelves.systems)
          if (shelf.games.isNotEmpty)
            Shelf(
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
        title: 'Brak wyników',
        subtitle: 'Spróbuj innego tytułu.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Text(
            'Wyniki · ${games.length}',
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

/// Trzy półki z pulsujących bloków — układ stoi, zanim przyjdą dane.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 0, kListBottomPad),
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
