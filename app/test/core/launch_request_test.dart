import 'package:droplet/core/launch/launch_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toMap carries every field with the documented keys', () {
    const r = LaunchRequest(
      package: 'p',
      activity: 'p.A',
      action: 'android.intent.action.VIEW',
      category: 'c',
      dataMode: DataMode.saf,
      romPath: '/roms/x.nsp',
      romTreeUri: 'content://tree',
      romTreePath: '/roms',
      extras: {'bootPath': tokenSaf, 'resumeState': false},
      clearTask: true,
    );
    expect(r.toMap(), {
      'package': 'p',
      'activity': 'p.A',
      'action': 'android.intent.action.VIEW',
      'category': 'c',
      'dataMode': 'saf',
      'romPath': '/roms/x.nsp',
      'romTreeUri': 'content://tree',
      'romTreePath': '/roms',
      'extras': {'bootPath': ' ROMSAF ', 'resumeState': false},
      'clearTask': true,
      'clearTop': false,
    });
  });

  test('RomTree.fromMap tolerates a missing path', () {
    final t = RomTree.fromMap({'uri': 'content://tree'});
    expect((t.uri, t.path), ('content://tree', null));
    expect(RomTree.fromMap({'uri': 'u', 'path': '/p'}).path, '/p');
  });

  test('the ROM tokens are the literals the native side looks for', () {
    expect((tokenRom, tokenSaf, tokenProvider), (
      ' ROM ',
      ' ROMSAF ',
      ' ROMPROVIDER ',
    ));
  });
}
