import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/downloads/local_state.dart';
import '../../core/session/providers.dart';
import '../../core/platform/downloader_port.dart';
import '../library/providers.dart';

final gameDetailProvider = FutureProvider.family<GameDetail, int>(
  (ref, id) => ref.watch(apiClientProvider).fetchGame(id),
);

/// A view of one game from the device index — the index itself is computed
/// once for the whole library, here only the read is left (and a test hook).
final localStateProvider = FutureProvider.family<LocalGameState, int>(
  (ref, id) async =>
      (await ref.watch(deviceIndexProvider.future))[id] ?? kNotInstalled,
);

/// Free bytes on the ROM folder's volume; null = unknown (we skip it).
final freeBytesProvider = FutureProvider.family<int?, String>(
  (ref, path) => ref.watch(downloaderPortProvider).freeBytes(path),
);
