import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/downloads/local_scanner.dart';
import '../../core/downloads/local_state.dart';
import '../../core/downloads/storage_settings.dart';
import '../../core/session/providers.dart';
import '../../core/platform/downloader_port.dart';

final gameDetailProvider = FutureProvider.family<GameDetail, int>(
  (ref, id) => ref.watch(apiClientProvider).fetchGame(id),
);

final localStateProvider = FutureProvider.family<LocalGameState, int>(
  (ref, id) async {
    final game = await ref.watch(gameDetailProvider(id).future);
    final settings = await ref.watch(storageSettingsProvider.future);
    final sizes = await scanSystemDir(settings.dirFor(game.systemCode));
    return diffGame(game.files, sizes, settings, game.systemCode);
  },
);

/// Wolne bajty na wolumenie katalogu ROMów; null = nieznane (pomijamy).
final freeBytesProvider = FutureProvider.family<int?, String>(
  (ref, path) => ref.watch(downloaderPortProvider).freeBytes(path),
);
