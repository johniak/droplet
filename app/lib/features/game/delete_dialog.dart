import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tokens.dart';
import '../../core/api/models.dart';
import '../../core/downloads/local_state.dart';
import '../../core/downloads/storage_settings.dart';
import '../library/providers.dart';

/// Deletes exactly the listed files — never a save. The game folder itself
/// goes only when [gameDir] is given and nothing is left inside it.
///
/// Synchronous IO on purpose: it is a handful of local files, and async
/// dart:io never completes inside `testWidgets` (the fake-async zone does
/// not pump the real event loop), which would make this path untestable.
Future<void> deleteLocalFiles(
  List<String> presentPaths, {
  String? gameDir,
}) async {
  for (final path in presentPaths) {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }
  // Katalog gry znika tylko wtedy, gdy nic w nim nie zostało — save'y i stany
  // zapisu obok ROM-u trzymają go przy życiu.
  if (gameDir != null) {
    final dir = Directory(gameDir);
    if (dir.existsSync() && dir.listSync().isEmpty) dir.deleteSync();
  }
}

Future<bool> confirmAndDelete(
  BuildContext context,
  WidgetRef ref,
  GameDetail game,
  LocalGameState local,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: kDialogBg,
      title: const Text('Usunąć z urządzenia?', style: TextStyle(color: kText)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final path in local.presentPaths)
            Text(
              path.split('/').last,
              style: const TextStyle(color: kTextDim, fontSize: 13),
            ),
          const SizedBox(height: 12),
          const Text(
            'Save\'y i stany zapisu nie zostaną usunięte.',
            style: TextStyle(color: kAccent, fontSize: 13),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Anuluj'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Usuń'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  final settings = await ref.read(storageSettingsProvider.future);
  await deleteLocalFiles(
    local.presentPaths,
    gameDir: settings.gameDir(game.systemCode, game.folder),
  );
  await ref.read(deviceIndexProvider.notifier).refresh();
  return true;
}
