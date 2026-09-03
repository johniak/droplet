import '../format.dart';

/// Head-room kept free on the device after a download (500 MB).
const kFreeSpaceMargin = 500 * 1024 * 1024;

bool hasEnoughSpace(int needed, int? free) =>
    free == null || free >= needed + kFreeSpaceMargin;

class InsufficientSpaceException implements Exception {
  const InsufficientSpaceException(this.needed, this.free);

  final int needed;
  final int free;

  @override
  String toString() =>
      'Not enough space: need ${formatBytes(needed)}, '
      '${formatBytes(free)} free';
}
