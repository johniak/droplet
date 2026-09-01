import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/session/providers.dart';
import '../library/widgets/cover_image.dart';
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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Error(
          message: error.toString(),
          onRetry: () => ref.invalidate(gameDetailProvider(gameId)),
        ),
        data: (game) => _Detail(game: game),
      ),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.game});

  final GameDetail game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = game.hasCover ? ref.watch(apiClientProvider) : null;
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
                CoverImage(
                  title: game.title,
                  url: client?.coverUrl(game.id, size: 'full') ?? '',
                  headers: client?.authHeaders ?? const {},
                  hasCover: game.hasCover,
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
              const Tooltip(
                message: 'Wkrótce',
                // Plain FilledButton (not .icon): the icon variant is a private
                // subclass that find.byType cannot match in widget tests.
                child: FilledButton(
                  onPressed: null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.download_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Pobierz'),
                    ],
                  ),
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
                for (final file in entry.value) _FileRow(file: file),
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
  const _FileRow({required this.file});

  final GameFileModel file;

  @override
  Widget build(BuildContext context) {
    final version = file.version.isEmpty ? '' : ' · ${file.version}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
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
