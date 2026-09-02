import 'dart:convert';
import 'dart:io';

import '../api/models.dart';

class CachedLibrary {
  const CachedLibrary({
    required this.systems,
    required this.games,
    required this.manifest,
    required this.savedAt,
  });

  final List<SystemModel> systems;
  final List<GameSummary> games;
  final List<ManifestEntry> manifest;
  final DateTime savedAt;
}

/// Last known library on disk, so the app still shows something without a
/// server.
///
/// Synchronous IO on purpose — see `deleteLocalFiles`: async dart:io never
/// completes inside `testWidgets`.
class LibraryCache {
  const LibraryCache(this.directory);

  final String directory;

  File get _file => File('$directory/library.json');

  Future<void> save(
    List<SystemModel> systems,
    List<GameSummary> games,
    List<ManifestEntry> manifest,
  ) async {
    _file.parent.createSync(recursive: true);
    _file.writeAsStringSync(
      jsonEncode({
        'saved_at': DateTime.now().toIso8601String(),
        'systems': [for (final s in systems) s.toJson()],
        'games': [for (final g in games) g.toJson()],
        'manifest': [for (final e in manifest) e.toJson()],
      }),
    );
  }

  /// Zwraca `null` także wtedy, gdy plik jest, ale nie daje się przeczytać w
  /// dzisiejszym kształcie — np. zapisany przez starszą wersję aplikacji, gdzie
  /// gry nie miały jeszcze `folder`. Wtedy lepiej odbudować bibliotekę z
  /// serwera niż pokazać błąd, którego użytkownik nie ma jak naprawić.
  Future<CachedLibrary?> load() async {
    if (!_file.existsSync()) return null;
    try {
      final data = jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
      return CachedLibrary(
        systems: [
          for (final s in data['systems'] as List)
            SystemModel.fromJson(s as Map<String, dynamic>),
        ],
        games: [
          for (final g in data['games'] as List)
            GameSummary.fromJson(g as Map<String, dynamic>),
        ],
        manifest: [
          for (final e in (data['manifest'] as List?) ?? const [])
            ManifestEntry.fromJson(e as Map<String, dynamic>),
        ],
        savedAt: DateTime.parse(data['saved_at'] as String),
      );
    } on Object {
      return null;
    }
  }
}
