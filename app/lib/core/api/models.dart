/// Dart mirror of the backend JSON contract (see the M3 plan).
enum FileRole { base, update, dlc, disc, support, other }

FileRole roleFrom(String raw) => FileRole.values.firstWhere(
      (r) => r.name == raw,
      orElse: () => FileRole.other,
    );

class SystemModel {
  const SystemModel({
    required this.id,
    required this.code,
    required this.name,
    required this.gameCount,
  });

  final int id;
  final String code;
  final String name;
  final int gameCount;

  factory SystemModel.fromJson(Map<String, dynamic> j) => SystemModel(
        id: j['id'] as int,
        code: j['code'] as String,
        name: j['name'] as String,
        gameCount: j['game_count'] as int,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'game_count': gameCount,
      };
}

class GameSummary {
  const GameSummary({
    required this.id,
    required this.title,
    required this.systemCode,
    required this.hasCover,
    required this.totalSize,
  });

  final int id;
  final String title;
  final String systemCode;
  final bool hasCover;
  final int totalSize;

  factory GameSummary.fromJson(Map<String, dynamic> j) => GameSummary(
        id: j['id'] as int,
        title: j['title'] as String,
        systemCode: j['system_code'] as String,
        hasCover: j['has_cover'] as bool,
        totalSize: j['total_size'] as int,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'system_code': systemCode,
        'has_cover': hasCover,
        'total_size': totalSize,
      };
}

class GameFileModel {
  const GameFileModel({
    required this.id,
    required this.name,
    required this.relativePath,
    required this.role,
    required this.discNumber,
    required this.version,
    required this.size,
  });

  final int id;
  final String name;
  final String relativePath;
  final FileRole role;
  final int? discNumber;
  final String version;
  final int size;

  factory GameFileModel.fromJson(Map<String, dynamic> j) => GameFileModel(
        id: j['id'] as int,
        name: j['name'] as String,
        relativePath: j['relative_path'] as String,
        role: roleFrom(j['role'] as String),
        discNumber: j['disc_number'] as int?,
        version: (j['version'] ?? '') as String,
        size: j['size'] as int,
      );
}

class GameDetail extends GameSummary {
  const GameDetail({
    required super.id,
    required super.title,
    required super.systemCode,
    required super.hasCover,
    required super.totalSize,
    required this.systemName,
    required this.files,
  });

  final String systemName;
  final List<GameFileModel> files;

  factory GameDetail.fromJson(Map<String, dynamic> j) => GameDetail(
        id: j['id'] as int,
        title: j['title'] as String,
        systemCode: j['system_code'] as String,
        hasCover: j['has_cover'] as bool,
        totalSize: j['total_size'] as int,
        systemName: j['system_name'] as String,
        files: (j['files'] as List)
            .map((f) => GameFileModel.fromJson(f as Map<String, dynamic>))
            .toList(),
      );
}

class GamePage {
  const GamePage({
    required this.count,
    required this.results,
    required this.hasNext,
  });

  final int count;
  final List<GameSummary> results;
  final bool hasNext;

  factory GamePage.fromJson(Map<String, dynamic> j) => GamePage(
        count: j['count'] as int,
        results: (j['results'] as List)
            .map((g) => GameSummary.fromJson(g as Map<String, dynamic>))
            .toList(),
        hasNext: j['next'] != null,
      );
}
