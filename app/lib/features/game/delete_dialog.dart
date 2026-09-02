import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tokens.dart';
import '../../core/downloads/local_state.dart';
import 'providers.dart';

/// Deletes exactly the listed files — never a directory, never a save.
///
/// Synchronous IO on purpose: it is a handful of local files, and async
/// dart:io never completes inside `testWidgets` (the fake-async zone does
/// not pump the real event loop), which would make this path untestable.
Future<void> deleteLocalFiles(List<String> presentPaths) async {
  for (final path in presentPaths) {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }
}

Future<bool> confirmAndDelete(
  BuildContext context,
  WidgetRef ref,
  int gameId,
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
  await deleteLocalFiles(local.presentPaths);
  ref.invalidate(localStateProvider(gameId));
  return true;
}
