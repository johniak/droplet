import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/models.dart';
import '../../core/downloads/download_manager.dart';
import '../../core/downloads/local_state.dart';
import '../../core/downloads/selection.dart';
import '../../core/downloads/space.dart';
import '../../core/downloads/storage_settings.dart';
import '../../core/format.dart';
import '../../core/session/providers.dart';
import '../../app/widgets/pulse_box.dart';
import '../library/providers.dart';
import '../library/widgets/cover_image.dart';
import 'delete_dialog.dart';
import 'providers.dart';

const roleLabels = {
  FileRole.base: 'Gra',
  FileRole.update: 'Aktualizacja',
  FileRole.dlc: 'DLC',
  FileRole.disc: 'Płyta',
  FileRole.support: 'Pozostałe',
  FileRole.other: 'Pozostałe',
};

String labelFor(GameFileModel file) => file.role == FileRole.disc
    ? '${roleLabels[FileRole.disc]} ${file.discNumber ?? ''}'.trim()
    : roleLabels[file.role]!;

class GameDetailScreen extends ConsumerWidget {
  const GameDetailScreen({super.key, required this.gameId});

  final int gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(gameDetailProvider(gameId));
    return Scaffold(
      body: detail.when(
        loading: () => const _DetailSkeleton(),
        error: (error, _) => _Error(
          message: error.toString(),
          onRetry: () => ref.invalidate(gameDetailProvider(gameId)),
        ),
        data: (game) => _Detail(game: game),
      ),
    );
  }
}

class _Detail extends ConsumerStatefulWidget {
  const _Detail({required this.game});

  final GameDetail game;

  @override
  ConsumerState<_Detail> createState() => _DetailState();
}

class _DetailState extends ConsumerState<_Detail> {
  late final Set<int> _selected = defaultSelection(widget.game.files);

  GameDetail get game => widget.game;

  int get _selectedSize => game.files
      .where((f) => _selected.contains(f.id))
      .fold(0, (sum, f) => sum + f.size);

  void _toggle(GameFileModel file, bool? on) => setState(() {
        if (on ?? false) {
          _selected.add(file.id);
        } else {
          _selected.remove(file.id);
        }
      });

  Future<void> _download(LocalGameState local) async {
    // await, not read: the session may not have been initialised yet.
    final session = (await ref.read(sessionProvider.future))!;
    final settings = await ref.read(storageSettingsProvider.future);
    try {
      await ref.read(downloadManagerProvider).downloadGame(
            game: game,
            selectedIds: _selected,
            local: local,
            serverUrl: session.serverUrl,
            authHeaders: {'Authorization': 'Token ${session.token}'},
            settings: settings,
          );
    } on PermissionDeniedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bez dostępu do plików nie pobiorę ROM-ów — '
            'przyznaj uprawnienie w ustawieniach',
          ),
        ),
      );
    } on InsufficientSpaceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = game.hasCover ? ref.watch(apiClientProvider) : null;
    final local = ref.watch(localStateProvider(game.id));
    final grouped = <String, List<GameFileModel>>{};
    for (final file in game.files) {
      grouped.putIfAbsent(labelFor(file), () => []).add(file);
    }
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 320,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                Hero(
                  tag: 'cover-${game.id}',
                  child: CoverImage(
                    title: game.title,
                    url: client?.coverUrl(game.id, size: 'full') ?? '',
                    headers: client?.authHeaders ?? const {},
                    hasCover: game.hasCover,
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.center,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, kBg],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          sliver: SliverList.list(
            children: [
              Text(
                game.title,
                style: const TextStyle(
                  color: kText,
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${game.systemName} · ${formatBytes(game.totalSize)}',
                style: const TextStyle(color: kTextDim, fontSize: 14),
              ),
              const SizedBox(height: 20),
              local.when(
                // A static placeholder, not a spinner: an indeterminate
                // animation never lets widget tests settle.
                loading: () => const FilledButton(
                  onPressed: null,
                  child: Text('Sprawdzam pliki...'),
                ),
                error: (e, _) => Text(
                  '$e',
                  style: const TextStyle(color: kTextDim),
                ),
                data: (state) => _Actions(
                  state: state,
                  selectedSize: _selectedSize,
                  // Offline the server is unreachable, so downloading is off.
                  onDownload:
                      ref.watch(isOfflineProvider) ? null : () => _download(state),
                  onDelete: () =>
                      confirmAndDelete(context, ref, game.id, state),
                ),
              ),
              const SizedBox(height: 28),
              for (final entry in grouped.entries) ...[
                Text(
                  entry.key,
                  style: const TextStyle(
                    color: kAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                for (final file in entry.value)
                  _FileRow(
                    file: file,
                    selected: _selected.contains(file.id),
                    onChanged: (on) => _toggle(file, on),
                  ),
                const SizedBox(height: 20),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.selected,
    required this.onChanged,
  });

  final GameFileModel file;
  final bool selected;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final version = file.version.isEmpty ? '' : ' · ${file.version}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Checkbox(value: selected, onChanged: onChanged),
          Expanded(
            child: Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kText, fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${formatBytes(file.size)}$version',
            style: const TextStyle(color: kTextDim, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kTextDim),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Ponów')),
            ],
          ),
        ),
      );
}


class _Actions extends StatelessWidget {
  const _Actions({
    required this.state,
    required this.selectedSize,
    required this.onDownload,
    required this.onDelete,
  });

  final LocalGameState state;
  final int selectedSize;
  final VoidCallback? onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    if (state.status == InstallStatus.installed && !state.updateAvailable) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle, color: kAccent, size: 18),
              SizedBox(width: 8),
              Text('Zainstalowana', style: TextStyle(color: kAccent)),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onDelete,
            child: const Text('Usuń z urządzenia'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton(
          onPressed: onDownload,
          child: Text(
            state.updateAvailable
                ? 'Pobierz aktualizację'
                : 'Pobierz (${formatBytes(selectedSize)})',
          ),
        ),
        if (state.presentPaths.isNotEmpty) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onDelete,
            child: const Text('Usuń z urządzenia'),
          ),
        ],
      ],
    );
  }
}


/// Keeps the shape of the game card while the manifest is on its way.
class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
        padding: EdgeInsets.zero,
        children: [
          const PulseBox(height: 320, radius: BorderRadius.zero),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: PulseBox(height: 26, width: 220),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: PulseBox(height: 14, width: 140),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: PulseBox(height: 40, width: 180, radius: BorderRadius.zero),
          ),
        ],
      );
}
