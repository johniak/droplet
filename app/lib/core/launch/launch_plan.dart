import '../api/models.dart';
import 'emulator_catalog.dart';
import 'launch_request.dart';

/// Planning failed before the native side was ever asked.
class LaunchPlanError implements Exception {
  const LaunchPlanError(this.code);

  /// 'no-boot-file' or 'saf-tree-missing'.
  final String code;
}

/// The one file that starts the game: a playlist over a first disc, a cue
/// over its tracks, a base ROM over updates and mods. `null` when the game
/// holds nothing bootable (mods or a readme only) — then Play stays hidden.
GameFileModel? bootFile(GameDetail game) {
  final files = game.files;
  bool ext(GameFileModel f, String e) => f.name.toLowerCase().endsWith(e);
  final m3u = files.where((f) => f.role == FileRole.support && ext(f, '.m3u'));
  if (m3u.isNotEmpty) return m3u.first;
  final disc1 = files.where(
    (f) => f.role == FileRole.disc && f.discNumber == 1,
  );
  if (disc1.isNotEmpty) return disc1.first;
  final cue = files.where((f) => f.role == FileRole.base && ext(f, '.cue'));
  if (cue.isNotEmpty) return cue.first;
  final base = files.where((f) => f.role == FileRole.base).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  if (base.isNotEmpty) return base.first;
  final rest = files.where(
    (f) =>
        f.role != FileRole.mod &&
        f.role != FileRole.other &&
        f.role != FileRole.update,
  );
  return rest.isEmpty ? null : rest.first;
}

/// Turns an ES-DE template into the map the native launcher understands.
/// URIs stay tokens ([tokenSaf], [tokenProvider]) — only Android can build
/// them. Throws [LaunchPlanError] when the template needs a SAF tree we do
/// not have, and [ArgumentError] on a token the catalogue should never hold.
LaunchRequest resolveTemplate({
  required EmulatorSpec spec,
  required String romPath,
  RomTree? tree,
}) {
  String? action;
  String? category;
  var mode = DataMode.none;
  var clearTask = false;
  var clearTop = false;
  final extras = <String, Object>{};
  String value(String raw) => raw
      .replaceAll('%ANDROIDPACKAGE%', spec.package)
      .replaceAll('%INTERNALDATA%', '/data/data')
      .replaceAll('%EXTERNALDATA%', '/storage/emulated/0')
      .replaceAll('%ROMSAF%', tokenSaf)
      .replaceAll('%ROMPROVIDER%', tokenProvider)
      .replaceAll('%ROM%', tokenRom);
  for (final token in spec.template
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)) {
    if (token == '%ACTIVITY_CLEAR_TASK%') {
      clearTask = true;
      continue;
    }
    if (token == '%ACTIVITY_CLEAR_TOP%') {
      clearTop = true;
      continue;
    }
    final eq = token.indexOf('=');
    if (eq < 0) throw ArgumentError('Unknown token $token in ${spec.id}');
    final key = token.substring(0, eq);
    final raw = token.substring(eq + 1);
    if (key == '%ACTION%') {
      action = raw;
    } else if (key == '%CATEGORY%') {
      category = raw;
    } else if (key == '%DATA%') {
      mode = switch (raw) {
        '%ROM%' => DataMode.path,
        '%ROMSAF%' => DataMode.saf,
        '%ROMPROVIDER%' => DataMode.provider,
        _ => throw ArgumentError('Bad %DATA% in ${spec.id}'),
      };
    } else if (key.startsWith('%EXTRABOOL_')) {
      extras[key.substring(11, key.length - 1)] = raw == 'true';
    } else if (key.startsWith('%EXTRA_')) {
      extras[key.substring(7, key.length - 1)] = value(raw);
    } else {
      throw ArgumentError('Unknown token $token in ${spec.id}');
    }
  }
  final needsSaf = mode == DataMode.saf || extras.values.contains(tokenSaf);
  if (needsSaf && tree == null) throw const LaunchPlanError('saf-tree-missing');
  return LaunchRequest(
    package: spec.package,
    activity: spec.activity,
    action: action,
    category: category,
    dataMode: mode,
    romPath: romPath,
    romTreeUri: tree?.uri,
    romTreePath: tree?.path,
    extras: extras,
    clearTask: clearTask,
    clearTop: clearTop,
  );
}
