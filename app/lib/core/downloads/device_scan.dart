import 'dart:io';

import '../api/models.dart';
import 'local_state.dart';
import 'storage_settings.dart';

/// Plik lub katalog w drzewie ROMów, którego nie zna żadna gra z manifestu.
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

  /// systemCode -> folder -> (ścieżka względem katalogu gry -> rozmiar)
  final Map<String, Map<String, Map<String, int>>> games;

  final List<UnknownEntry> unknown;
}

String _rel(FileSystemEntity e, Directory base) =>
    e.path.substring(base.path.length + 1).replaceAll(Platform.pathSeparator, '/');

Map<String, int> _sizesUnder(Directory dir) => {
      for (final e in dir.listSync(recursive: true))
        if (e is File) _rel(e, dir): e.lengthSync(),
    };

/// Jeden synchroniczny przebieg po katalogach systemów (patrz zasada o dart:io
/// w testach widgetowych). Foldery spoza [knownFolderKeys] i pliki luzem
/// lądują w [DeviceIndex.unknown].
DeviceIndex scanDevice(
  StorageSettings settings,
  Iterable<String> systemCodes,
  Set<String> knownFolderKeys,
) {
  final games = <String, Map<String, Map<String, int>>>{};
  final unknown = <UnknownEntry>[];
  for (final code in systemCodes) {
    final dir = Directory(settings.dirFor(code));
    if (!dir.existsSync()) continue;
    for (final e in dir.listSync()) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (e is File) {
        unknown.add(
          UnknownEntry(
            systemCode: code,
            path: e.path,
            bytes: e.lengthSync(),
            isDirectory: false,
          ),
        );
      } else if (e is Directory) {
        final sizes = _sizesUnder(e);
        if (knownFolderKeys.contains('$code/$name')) {
          games.putIfAbsent(code, () => {})[name] = sizes;
        } else {
          unknown.add(
            UnknownEntry(
              systemCode: code,
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

/// Stan każdej gry z manifestu policzony z jednego skanu — bez zapytania
/// do serwera i bez wchodzenia na dysk per kafelek.
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
