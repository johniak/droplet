import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/selection.dart';
import 'package:flutter_test/flutter_test.dart';

GameFileModel f(int id, FileRole role, {String version = ''}) => GameFileModel(
      id: id,
      name: 'f$id',
      relativePath: 'p/f$id',
      role: role,
      discNumber: null,
      version: version,
      size: 1,
    );

void main() {
  test('versionNumber extracts digits', () {
    expect(versionNumber('v196608'), 196608);
    expect(versionNumber('v1.2.6'), 126);
    expect(versionNumber(''), 0);
  });

  test('only newest update selected', () {
    final sel = defaultSelection([
      f(1, FileRole.base),
      f(2, FileRole.update, version: 'v65536'),
      f(3, FileRole.update, version: 'v196608'),
      f(4, FileRole.dlc),
    ]);
    expect(sel, {1, 3, 4});
  });

  test('discs and support always selected', () {
    final sel = defaultSelection([
      f(1, FileRole.disc),
      f(2, FileRole.disc),
      f(3, FileRole.support),
    ]);
    expect(sel, {1, 2, 3});
  });

  test('mods are always part of the default selection', () {
    final files = [
      f(1, FileRole.base),
      f(2, FileRole.update, version: 'v1'),
      f(3, FileRole.mod),
    ];
    expect(defaultSelection(files), {1, 2, 3});
  });
}
