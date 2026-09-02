from django.urls import path

from . import api, download

urlpatterns = [
    path("scan/", api.trigger_scan, name="trigger-scan"),
    path("systems/", api.SystemListView.as_view(), name="systems"),
    path("games/", api.GameListView.as_view(), name="games"),
    path("games/<int:pk>/", api.GameDetailView.as_view(), name="game-detail"),
    path("manifest/", api.ManifestView.as_view(), name="manifest"),
    path(
        "files/<int:pk>/download", download.file_download, name="file-download"
    ),
]
