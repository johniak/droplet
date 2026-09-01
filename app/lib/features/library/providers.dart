import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/session/providers.dart';

final systemsProvider = FutureProvider<List<SystemModel>>(
  (ref) => ref.watch(apiClientProvider).fetchSystems(),
);

/// Riverpod 3 dropped StateProvider, so the two pieces of UI state are plain
/// notifiers with an explicit setter.
class SelectedSystem extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? code) => state = code;
}

final selectedSystemProvider =
    NotifierProvider<SelectedSystem, String?>(SelectedSystem.new);

class SearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) => state = query;
}

final searchQueryProvider =
    NotifierProvider<SearchQuery, String>(SearchQuery.new);

/// Walks every page: a single-user library fits in memory, and the grid then
/// scrolls without pagination stutter.
final gamesProvider = FutureProvider<List<GameSummary>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final system = ref.watch(selectedSystemProvider);
  final search = ref.watch(searchQueryProvider);
  final all = <GameSummary>[];
  var page = 1;
  while (true) {
    final result = await client.fetchGames(
      system: system,
      search: search,
      page: page,
    );
    all.addAll(result.results);
    if (!result.hasNext) return all;
    page += 1;
  }
});
