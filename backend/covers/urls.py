from django.urls import path

from . import api

urlpatterns = [
    path("games/<int:game_id>/cover", api.game_cover, name="game-cover"),
]
