from django.urls import path

from . import api

urlpatterns = [
    path("scan/", api.trigger_scan, name="trigger-scan"),
    path("systems/", api.SystemListView.as_view(), name="systems"),
    path("games/", api.GameListView.as_view(), name="games"),
]
