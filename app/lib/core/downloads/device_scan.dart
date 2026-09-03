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

/// Ścieżka bazowa bez końcowych separatorów: `Directory('/roms/snes/')` i
/// `Directory('/roms/snes')` mają dawać te same ścieżki względne.
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

/// Kropka na początku dowolnego segmentu = wpis ukryty (ta sama zasada co w
/// skanerze backendu), więc `.nomedia`, `.thumbnails/` czy `.DS_Store` nie
/// trafiają ani do rozmiarów gry, ani na listę nieznanych.
bool _hidden(String relativePath) =>
    relativePath.split('/').any((segment) => segment.startsWith('.'));

/// Katalog bez prawa odczytu (albo zniknięty w trakcie skanu) pomijamy — reszta
/// drzewa ma się policzyć mimo to. `followLinks: false`: symlink nie ma
/// wciągać skanu w cudze drzewo ani w pętlę.
List<FileSystemEntity> _entriesOf(Directory dir) {
  try {
    return dir.listSync(followLinks: false);
  } on FileSystemException {
    return const [];
  }
}

/// Ręczna rekurencja zamiast `listSync(recursive: true)`: ta buduje listę na
/// raz, więc jeden nieczytelny podkatalog gubi wszystkie pliki gry.
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

/// Klucz znanego folderu gry: **rozwiązany** katalog, a nie kod systemu. Dwa
/// systemy mogą wskazywać ten sam podkatalog (gb i gbc → `gameboy`) i wtedy
/// gra jednego z nich nie może uchodzić za nieznany folder drugiego.
String knownFolderKey(StorageSettings settings, String code, String folder) =>
    '${settings.dirFor(code)}/$folder';

/// Ścieżka naprawdę leżąca w drzewie ROMów: pod [baseDir] i bez segmentu „..”,
/// który wyprowadziłby ją z powrotem na zewnątrz mimo pasującego prefiksu.
bool insideBaseDir(String path, String baseDir) =>
    path.startsWith('$baseDir/') && !path.split('/').contains('..');

/// Kody systemów zgrupowane po rozwiązanym katalogu, z zachowaniem kolejności.
/// Katalog spoza drzewa ROMów w ogóle nie wchodzi do skanu — inaczej złe
/// nadpisanie kazałoby skanować (i kasować) cudze pliki.
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

/// Jeden synchroniczny przebieg po katalogach systemów (patrz zasada o dart:io
/// w testach widgetowych). Foldery spoza [knownFolderKeys] (klucze z
/// [knownFolderKey]) i pliki luzem lądują w [DeviceIndex.unknown].
DeviceIndex scanDevice(
  StorageSettings settings,
  Iterable<String> systemCodes,
  Set<String> knownFolderKeys,
) {
  final games = <String, Map<String, Map<String, int>>>{};
  final unknown = <UnknownEntry>[];
  for (final entry in _dirsToScan(settings, systemCodes).entries) {
    final dir = Directory(entry.key);
    // Wspólny katalog skanujemy raz; nieznane wpisy przypisujemy pierwszemu
    // kodowi, a rozmiary gier — każdemu, bo manifest szuka po swoim kodzie.
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
