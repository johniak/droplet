import 'package:droplet/core/downloads/space.dart';
import 'package:droplet/core/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unknown free space skips the check', () {
    expect(hasEnoughSpace(1000, null), true);
  });

  test('needs the margin on top of the download', () {
    expect(hasEnoughSpace(1000, 1000 + kFreeSpaceMargin), true);
    expect(hasEnoughSpace(1000, 1000 + kFreeSpaceMargin - 1), false);
  });

  test('the exception says how much is needed and free', () {
    // formatBytes divides by 1024, so the message is in GiB-sized "GB".
    const e = InsufficientSpaceException(4200000000, 1100000000);
    expect(e.toString(), contains(formatBytes(4200000000)));
    expect(e.toString(), contains(formatBytes(1100000000)));
    expect(e.toString(), startsWith('Za mało miejsca'));
  });
}
