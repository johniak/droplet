import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/session/providers.dart';

final gameDetailProvider = FutureProvider.family<GameDetail, int>(
  (ref, id) => ref.watch(apiClientProvider).fetchGame(id),
);
