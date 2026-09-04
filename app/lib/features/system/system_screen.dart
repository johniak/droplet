import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/input/gamepad.dart';
import '../../app/layout.dart';
import '../../app/tokens.dart';
import '../../app/widgets/circle_icon_button.dart';
import '../../app/widgets/focus_glow.dart';
import '../../app/widgets/primary_button.dart';
import '../../app/widgets/pulse_box.dart';
import '../../core/api/models.dart';
import '../../core/errors.dart';
import '../library/providers.dart';
import '../library/widgets/games_grid.dart';
import '../library/widgets/search_field.dart';
import '../library/widgets/sort_menu.dart';

List<GameSummary> filterByQuery(List<GameSummary> games, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return games;
  return [
    for (final g in games)
      if (g.title.toLowerCase().contains(q)) g,
  ];
}

class SystemScreen extends ConsumerStatefulWidget {
  const SystemScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<SystemScreen> createState() => _SystemScreenState();
}

class _SystemScreenState extends ConsumerState<SystemScreen> {
  var _query = '';

  /// Y hands the focus to the field; the field itself never grabs it.
  final _searchNode = FocusNode();

  @override
  void dispose() {
    _searchNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final systems = ref.watch(systemsProvider);
    final games = ref.watch(systemGamesProvider(widget.code));
    final system = systems.value
        ?.where((s) => s.code == widget.code)
        .firstOrNull;
    final search = SearchField(
      hint: 'Search in ${system?.name ?? widget.code}',
      focusNode: _searchNode,
      onChanged: (v) => setState(() => _query = v),
    );
    return Actions(
      actions: {
        FocusSearchIntent: CallbackAction<FocusSearchIntent>(
          onInvoke: (_) {
            _searchNode.requestFocus();
            return null;
          },
        ),
      },
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: Scaffold(
          body: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = isWideWidth(constraints.maxWidth);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Header(
                      system: system,
                      code: widget.code,
                      search: wide ? search : null,
                    ),
                    if (!wide)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: search,
                      ),
                    const _FilterChips(),
                    Expanded(
                      child: systems.when(
                        loading: () => const _Skeleton(),
                        error: (e, _) => _Message(
                          humanizeError(e),
                          action: 'Retry',
                          onAction: () =>
                              ref.invalidate(librarySnapshotProvider),
                        ),
                        data: (_) {
                          if (system == null) {
                            return const _Message('Unknown system');
                          }
                          final list = filterByQuery(
                            games.value ?? const [],
                            _query,
                          );
                          if (list.isEmpty) {
                            return const _Message('Nothing matches');
                          }
                          return GamesGrid(
                            games: list,
                            autofocusFirst: true,
                            routeFor: (id) => '/system/${widget.code}/game/$id',
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.system, required this.code, this.search});

  /// Wide layout: the search field lives in the header row.
  final Widget? search;

  final SystemModel? system;
  final String code;

  static String _plural(int n) => n == 1 ? '1 game' : '$n games';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(librarySnapshotProvider).value?.games ?? const [];
    final own = [
      for (final g in all)
        if (g.systemCode == code) g,
    ];
    final installed = ref.watch(installedIdsProvider);
    final onDevice = own.where((g) => installed.contains(g.id)).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 4),
      child: Row(
        children: [
          CircleIconButton(
            key: const Key('back-button'),
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onPressed: () => context.pop(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  system?.name ?? code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kText,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  '${_plural(own.length)} · $onDevice on device',
                  style: const TextStyle(color: kTextDim, fontSize: 12),
                ),
              ],
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
}

class _FilterChips extends ConsumerWidget {
  const _FilterChips();

  static const _labels = {
    SystemFilter.all: 'All',
    SystemFilter.installed: 'On device',
    SystemFilter.updatable: 'Updates',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(systemFilterProvider);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        children: [
          for (final entry in _labels.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FocusGlow(
                scale: 1,
                borderRadius: 999,
                onTap: () =>
                    ref.read(systemFilterProvider.notifier).select(entry.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected == entry.key ? kAccent : kGlass,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: selected == entry.key ? kAccent : kGlassBorder,
                    ),
                  ),
                  child: Text(
                    entry.value,
                    style: TextStyle(
                      color: selected == entry.key ? kBgBottom : kText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(32),
    children: [
      const SizedBox(height: 60),
      Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: kTextDim, fontSize: 15),
      ),
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

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => GridView.builder(
    padding: EdgeInsets.fromLTRB(16, 12, 16, listBottomPad(context)),
    gridDelegate: GamesGrid.delegateFor(const []),
    itemCount: 6,
    itemBuilder: (_, __) => const PulseBox(),
  );
}
