import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/downloads/local_state.dart';
import '../../core/session/providers.dart';
import '../../core/platform/downloader_port.dart';
import '../library/providers.dart';

final gameDetailProvider = FutureProvider.family<GameDetail, int>(
  (ref, id) => ref.watch(apiClientProvider).fetchGame(id),
);

/// Widok na jedną grę z indeksu urządzenia — sam indeks liczy się raz dla
/// całej biblioteki, tu zostaje tylko odczyt (i punkt zaczepienia dla testów).
final localStateProvider = FutureProvider.family<LocalGameState, int>(
  (ref, id) async =>
      (await ref.watch(deviceIndexProvider.future))[id] ?? kNotInstalled,
);

/// Wolne bajty na wolumenie katalogu ROMów; null = nieznane (pomijamy).
final freeBytesProvider = FutureProvider.family<int?, String>(
  (ref, path) => ref.watch(downloaderPortProvider).freeBytes(path),
);
