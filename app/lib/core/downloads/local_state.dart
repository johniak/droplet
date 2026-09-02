import '../api/models.dart';
import 'selection.dart';
import 'storage_settings.dart';

enum InstallStatus { none, partial, installed }

class LocalGameState {
  const LocalGameState({
    required this.status,
    required this.updateAvailable,
    required this.missing,
    required this.presentPaths,
  });

  final InstallStatus status;

  /// The base game is on disk but the newest update from the server is not.
  final bool updateAvailable;

  /// Files from the default selection that are not on disk yet.
  final List<GameFileModel> missing;

  /// Absolute paths of this game's files that exist on disk — including files
  /// outside the selection (e.g. an older update), because this is the list
  /// used for deleting.
  final List<String> presentPaths;
}

LocalGameState diffGame(
  List<GameFileModel> files,
  Map<String, int> localSizesByName,
  StorageSettings settings,
  String systemCode,
  String folder,
) {
  bool present(GameFileModel file) => localSizesByName[file.name] == file.size;

  final selection = defaultSelection(files);
  final wanted = files.where((f) => selection.contains(f.id)).toList();
  final missing = wanted.where((f) => !present(f)).toList();

  final status = missing.isEmpty
      ? InstallStatus.installed
      : missing.length == wanted.length
          ? InstallStatus.none
          : InstallStatus.partial;

  final base = files.where((f) => f.role == FileRole.base);
  final newestUpdate = wanted.where((f) => f.role == FileRole.update);
  final updateAvailable = base.isNotEmpty &&
      base.every(present) &&
      newestUpdate.isNotEmpty &&
      newestUpdate.any((f) => !present(f));

  final presentPaths = [
    for (final file in files)
      if (present(file)) settings.pathFor(systemCode, folder, file.name),
  ];

  return LocalGameState(
    status: status,
    updateAvailable: updateAvailable,
    missing: missing,
    presentPaths: presentPaths,
  );
}
