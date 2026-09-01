from rest_framework import serializers

from .models import System


class SystemSerializer(serializers.ModelSerializer):
    game_count = serializers.IntegerField(read_only=True)

    class Meta:
        model = System
        fields = ["id", "code", "name", "game_count", "sort_order"]
