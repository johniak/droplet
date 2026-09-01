import '../api/models.dart';

int versionNumber(String version) {
  final digits = version.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? 0 : int.parse(digits);
}

/// Everything but updates is selected; of the updates only the newest one.
Set<int> defaultSelection(List<GameFileModel> files) {
  final selected = <int>{};
  GameFileModel? newestUpdate;
  for (final file in files) {
    if (file.role == FileRole.update) {
      if (newestUpdate == null ||
          versionNumber(file.version) > versionNumber(newestUpdate.version)) {
        newestUpdate = file;
      }
    } else {
      selected.add(file.id);
    }
  }
  if (newestUpdate != null) selected.add(newestUpdate.id);
  return selected;
}
