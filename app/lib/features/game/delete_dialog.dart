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
  // The game folder goes only when nothing is left inside it — saves and save
  // states sitting next to the ROM keep it alive. Empty subfolders (disc1/,
  // disc2/ once their ROMs are gone) would keep it alive on their own, so they
  // go first — deepest first, so the parent gets a chance to become empty.
  if (gameDir == null) return;
  final dir = Directory(gameDir);
  if (!dir.existsSync()) return;
  final nested = [
    for (final e in dir.listSync(recursive: true, followLinks: false))
      if (e is Directory) e,
  ]..sort((a, b) => b.path.length.compareTo(a.path.length));
  for (final child in [...nested, dir]) {
    if (child.listSync(followLinks: false).isEmpty) child.deleteSync();
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
      title: const Text('Delete from device?', style: TextStyle(color: kText)),
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
            'Saves and save states will be kept.',
            style: TextStyle(color: kAccent, fontSize: 13),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
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
