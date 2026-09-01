from django.http import FileResponse, Http404
from rest_framework.decorators import api_view

from library.models import Game

from .paths import full_path, thumb_path


@api_view(["GET"])
def game_cover(request, game_id: int):
    if not Game.objects.filter(pk=game_id, cover__isnull=False).exists():
        raise Http404
    size = request.query_params.get("size", "thumb")
    path = full_path(game_id) if size == "full" else thumb_path(game_id)
    if not path.exists():
        raise Http404
    resp = FileResponse(open(path, "rb"), content_type="image/png")
    resp["Cache-Control"] = "private, max-age=86400"
    return resp
