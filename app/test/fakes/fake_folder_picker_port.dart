import 'package:droplet/core/platform/folder_picker_port.dart';

/// Returns a scripted path (or `null` for "cancelled") and counts the calls.
class FakeFolderPickerPort implements FolderPickerPort {
  FakeFolderPickerPort(this.result);

  final String? result;
  int calls = 0;

  @override
  Future<String?> pickDirectory() async {
    calls++;
    return result;
  }
}
