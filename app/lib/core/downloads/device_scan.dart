import 'dart:io';

import '../api/models.dart';
import 'local_state.dart';
import 'storage_settings.dart';

/// A file or folder in the ROM tree that no game in the manifest knows about.
class UnknownEntry {
  const UnknownEntry({
    required this.systemCode,
    required this.path,
    required this.bytes,
    required this.isDirectory,
  });

  final String systemCode;
  final String path;
  final int bytes;
  final bool isDirectory;
}

class DeviceIndex {
  const DeviceIndex({required this.games, required this.unknown});

  /// systemCode -> folder -> (path relative to the game folder -> size)
  final Map<String, Map<String, Map<String, int>>> games;

  final List<UnknownEntry> unknown;
}

/// Base path without trailing separators: `Directory('/roms/snes/')` and
/// `Directory('/roms/snes')` must yield the same relative paths.
String _basePath(Directory base) {
  var path = base.path;
  while (path.length > 1 &&
      (path.endsWith('/') || path.endsWith(Platform.pathSeparator))) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

String _rel(FileSystemEntity e, String base) => e.path
    .substring(base.length + 1)
    .replaceAll(Platform.pathSeparator, '/');

/// A dot at the start of any segment means a hidden entry (the same rule as in
/// the backend scanner), so `.nomedia`, `.thumbnails/` or `.DS_Store` end up
/// neither in the game sizes nor on the unknown list.
bool _hidden(String relativePath) =>
    relativePath.split('/').any((segment) => segment.startsWith('.'));

/// An unreadable directory (or one that vanished mid-scan) is skipped — the
/// rest of the tree must still be counted. `followLinks: false`: a symlink must
/// not drag the scan into someone else's tree or into a loop.
List<FileSystemEntity> _entriesOf(Directory dir) {
  try {
    return dir.listSync(followLinks: false);
  } on FileSystemException {
    return const [];
  }
}

/// Manual recursion instead of `listSync(recursive: true)`: that one builds the
/// list in one go, so a single unreadable subdirectory loses every file of the
/// game.
Map<String, int> sizesUnder(Directory dir) {
  final base = _basePath(dir);
  final sizes = <String, int>{};
  final queue = <Directory>[dir];
  while (queue.isNotEmpty) {
    for (final e in _entriesOf(queue.removeLast())) {
      final rel = _rel(e, base);
      if (_hidden(rel)) continue;
      if (e is File) {
        sizes[rel] = e.lengthSync();
      } else if (e is Directory) {
        queue.add(e);
      }
    }
  }
  return sizes;
}

/// Key of a known game folder: the **resolved** directory, not the system code.
/// Two systems can point at the same subdirectory (gb and gbc → `gameboy`) and
/// then a game of one must not pass for an unknown folder of the other.
String knownFolderKey(StorageSettings settings, String code, String folder) =>
    '${settings.dirFor(code)}/$folder';

/// A path that really sits inside the ROM tree: under [baseDir] and without a
/// '..' segment that would lead back out despite the matching prefix.
bool insideBaseDir(String path, String baseDir) =>
    path.startsWith('$baseDir/') && !path.split('/').contains('..');

/// System codes grouped by resolved directory, keeping the original order.
/// A directory outside the ROM tree never enters the scan — otherwise a bad
/// override would make us scan (and delete) someone else's files.
Map<String, List<String>> _dirsToScan(
  StorageSettings settings,
  Iterable<String> systemCodes,
) {
  final byDir = <String, List<String>>{};
  for (final code in systemCodes) {
    final path = settings.dirFor(code);
    if (!insideBaseDir(path, settings.baseDir)) continue;
    byDir.putIfAbsent(path, () => []).add(code);
  }
  return byDir;
}

/// One synchronous pass over the system directories (see the dart:io rule for
/// widget tests). Folders outside [knownFolderKeys] (keys from
/// [knownFolderKey]) and loose files land in [DeviceIndex.unknown].
DeviceIndex scanDevice(
  StorageSettings settings,
  Iterable<String> systemCodes,
  Set<String> knownFolderKeys,
) {
  final games = <String, Map<String, Map<String, int>>>{};
  final unknown = <UnknownEntry>[];
  for (final entry in _dirsToScan(settings, systemCodes).entries) {
    final dir = Directory(entry.key);
    // A shared directory is scanned once; unknown entries go to the first
    // code, game sizes to every code, as the manifest looks up by its own.
    final codes = entry.value;
    if (!dir.existsSync()) continue;
    for (final e in _entriesOf(dir)) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (_hidden(name)) continue;
      if (e is File) {
        unknown.add(
          UnknownEntry(
            systemCode: codes.first,
            path: e.path,
            bytes: e.lengthSync(),
            isDirectory: false,
          ),
        );
      } else if (e is Directory) {
        final sizes = sizesUnder(e);
        if (knownFolderKeys.contains('${entry.key}/$name')) {
          for (final code in codes) {
            games.putIfAbsent(code, () => {})[name] = sizes;
          }
        } else {
          unknown.add(
            UnknownEntry(
              systemCode: codes.first,
              path: e.path,
              bytes: sizes.values.fold(0, (a, b) => a + b),
              isDirectory: true,
            ),
          );
        }
      }
    }
  }
  return DeviceIndex(games: games, unknown: unknown);
}

/// State of every game in the manifest computed from a single scan — without
/// a server request and without touching the disk per tile.
Map<int, LocalGameState> buildLocalStates(
  List<ManifestEntry> manifest,
  DeviceIndex index,
  StorageSettings settings,
) =>
    {
      for (final entry in manifest)
        entry.gameId: diffGame(
          entry.files,
          index.games[entry.systemCode]?[entry.folder] ?? const {},
          settings,
          entry.systemCode,
          entry.folder,
        ),
    };
