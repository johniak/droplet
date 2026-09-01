import posixpath

from rest_framework import serializers

from .models import Game, GameFile, System

ROLE_ORDER = {
    "base": 0,
    "update": 1,
    "dlc": 2,
    "disc": 3,
    "support": 4,
    "other": 5,
}


class SystemSerializer(serializers.ModelSerializer):
    game_count = serializers.IntegerField(read_only=True)

    class Meta:
        model = System
        fields = ["id", "code", "name", "game_count", "sort_order"]


class GameListSerializer(serializers.ModelSerializer):
    system_code = serializers.CharField(source="system.code", read_only=True)
    has_cover = serializers.BooleanField(read_only=True)
    total_size = serializers.IntegerField(read_only=True)

    class Meta:
        model = Game
        fields = ["id", "title", "system_code", "has_cover", "total_size"]


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
        return posixpath.basename(obj.relative_path)


class GameDetailSerializer(GameListSerializer):
    system_name = serializers.CharField(source="system.name", read_only=True)
    files = serializers.SerializerMethodField()

    class Meta(GameListSerializer.Meta):
        fields = GameListSerializer.Meta.fields + ["system_name", "files"]

    def get_files(self, obj):
        files = sorted(
            obj.files.all(),
            key=lambda f: (
                ROLE_ORDER.get(f.role, 9),
                f.disc_number or 0,
                f.relative_path,
            ),
        )
        return GameFileSerializer(files, many=True).data
