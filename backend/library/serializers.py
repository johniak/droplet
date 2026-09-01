from rest_framework import serializers

from .models import Game, System


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
