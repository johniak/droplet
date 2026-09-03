import posixpath

from rest_framework import serializers

from .models import Game, GameFile, System

ROLE_ORDER = {
    "base": 0,
    "update": 1,
    "dlc": 2,
    "disc": 3,
    "support": 4,
    "mod": 5,
    "other": 6,
}


class SystemSerializer(serializers.ModelSerializer):
    game_count = serializers.IntegerField(read_only=True)

    class Meta:
        model = System
        fields = ["id", "code", "name", "game_count", "sort_order"]


def _name_within_game(file: GameFile) -> str:
    folder = file.game.folder
    if folder and file.relative_path.startswith(folder + "/"):
        return file.relative_path[len(folder) + 1 :]
    return posixpath.basename(file.relative_path)


def sorted_files(game):
    return sorted(
        game.files.all(),
        key=lambda f: (ROLE_ORDER.get(f.role, 9), f.disc_number or 0, f.relative_path),
    )


class GameListSerializer(serializers.ModelSerializer):
    system_code = serializers.CharField(source="system.code", read_only=True)
    has_cover = serializers.BooleanField(read_only=True)
    total_size = serializers.IntegerField(read_only=True)
    folder = serializers.SerializerMethodField()

    class Meta:
        model = Game
        fields = ["id", "title", "system_code", "has_cover", "total_size", "folder"]

    def get_folder(self, obj):
        return posixpath.basename(obj.folder)


class GameFileSerializer(serializers.ModelSerializer):
    name = serializers.SerializerMethodField()

    class Meta:
        model = GameFile
        fields = [
            "id",
            "name",
            "relative_path",
            "role",
            "disc_number",
            "version",
            "size",
        ]

    def get_name(self, obj):
        return _name_within_game(obj)


class GameDetailSerializer(GameListSerializer):
    system_name = serializers.CharField(source="system.name", read_only=True)
    files = serializers.SerializerMethodField()

    class Meta(GameListSerializer.Meta):
        fields = GameListSerializer.Meta.fields + ["system_name", "files"]

    def get_files(self, obj):
        return GameFileSerializer(sorted_files(obj), many=True).data


class ManifestFileSerializer(serializers.ModelSerializer):
    name = serializers.SerializerMethodField()

    class Meta:
        model = GameFile
        fields = ["id", "name", "role", "version", "disc_number", "size"]

    def get_name(self, obj):
        return _name_within_game(obj)


class ManifestEntrySerializer(serializers.ModelSerializer):
    system_code = serializers.CharField(source="system.code", read_only=True)
    folder = serializers.SerializerMethodField()
    files = serializers.SerializerMethodField()

    class Meta:
        model = Game
        fields = ["id", "system_code", "folder", "files"]

    def get_folder(self, obj):
        return posixpath.basename(obj.folder)

    def get_files(self, obj):
        return ManifestFileSerializer(sorted_files(obj), many=True).data
