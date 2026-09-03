// coverage:ignore-file
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Thin adapter over file_picker's directory picker (SAF tree picker on
/// Android). Returns a plain path for internal storage, `null` when the user
/// cancels. Screens depend on this port and are tested on fakes.
abstract class FolderPickerPort {
  Future<String?> pickDirectory();
}

class FilePickerFolderPort implements FolderPickerPort {
  const FilePickerFolderPort();

  @override
  Future<String?> pickDirectory() => FilePicker.getDirectoryPath();
}

final folderPickerPortProvider = Provider<FolderPickerPort>(
  (ref) => const FilePickerFolderPort(),
);
