/// How the native side fills `Intent.data` from [LaunchRequest.romPath].
enum DataMode {
  /// No data URI at all — the ROM travels in an extra.
  none,

  /// `file://` path (only emulators that still accept it).
  path,

  /// `content://` document URI inside the persisted SAF tree.
  saf,

  /// `content://` URI from our own FileProvider.
  provider,
}

/// Everything the native launcher needs to build one Intent. Values that
/// depend on a URI are left as tokens ([tokenRom], [tokenSaf],
/// [tokenProvider]); Dart never builds Android URIs.
class LaunchRequest {
  const LaunchRequest({
    required this.package,
    this.activity,
    this.action,
    this.category,
    required this.dataMode,
    required this.romPath,
    this.romTreeUri,
    this.romTreePath,
    this.extras = const {},
    this.clearTask = false,
    this.clearTop = false,
  });

  final String package;
  final String? activity;
  final String? action;
  final String? category;

  /// How `data` is filled from [romPath].
  final DataMode dataMode;

  /// Absolute path of the file to boot.
  final String romPath;

  /// Persisted SAF tree (for `saf` mode and `saf` extras).
  final String? romTreeUri;

  /// The path the tree points at (for the relative path computation).
  final String? romTreePath;

  /// String values may hold the tokens below; bool values stay bool.
  final Map<String, Object> extras;

  final bool clearTask;
  final bool clearTop;

  Map<String, Object?> toMap() => {
    'package': package,
    'activity': activity,
    'action': action,
    'category': category,
    'dataMode': dataMode.name,
    'romPath': romPath,
    'romTreeUri': romTreeUri,
    'romTreePath': romTreePath,
    'extras': extras,
    'clearTask': clearTask,
    'clearTop': clearTop,
  };
}

/// The literal strings replaced natively by the absolute path, the SAF
/// document URI and the FileProvider URI.
const tokenRom = ' ROM ';
const tokenSaf = ' ROMSAF ';
const tokenProvider = ' ROMPROVIDER ';

/// A SAF tree the user granted us: its URI and, for internal storage, the
/// path it points at.
class RomTree {
  const RomTree({required this.uri, this.path});

  final String uri;
  final String? path;

  factory RomTree.fromMap(Map<Object?, Object?> map) =>
      RomTree(uri: map['uri']! as String, path: map['path'] as String?);
}
