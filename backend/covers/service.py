"""Matching games to libretro boxarts and caching them on disk."""

from PIL import Image

from library.models import Game, System

from .matching import best_match
from .models import Cover
from .paths import ensure_dirs, full_path, thumb_path
from .thumbnails import download_boxart, fetch_index
from .titledb import base_title_id, download_image, icon_urls

THUMB_WIDTH = 256


def _make_thumb(game_id: int) -> None:
    img = Image.open(full_path(game_id)).convert("RGBA")
    ratio = THUMB_WIDTH / img.width
    img = img.resize(
        (THUMB_WIDTH, max(1, int(img.height * ratio))), Image.Resampling.LANCZOS
    )
    thumb = thumb_path(game_id)
    thumb.parent.mkdir(parents=True, exist_ok=True)
    img.save(thumb, format="PNG")


def match_game(game: Game, index_names: list[str]) -> bool:
    existing = Cover.objects.filter(game=game).first()
    if existing and existing.is_manual:
        return False
    result = best_match(game.normalized_title, index_names)
    if result is None:
        return False
    download_boxart(game.system.thumbnail_repo, result.name, full_path(game.id))
    _make_thumb(game.id)
    Cover.objects.update_or_create(
        game=game,
        defaults={
            "source": Cover.Source.LIBRETRO,
            "match_name": result.name,
            "score": result.score,
            "is_manual": False,
        },
    )
    return True


def match_switch(system: System, stats: dict) -> None:
    """Switch: okładka = ikona eShopu gry o tym samym title id co plik bazowy."""
    games = [
        g for g in system.games.filter(cover__isnull=True)
    ]
    by_tid = {}
    for game in games:
        tid = base_title_id(game)
        if tid is None:
            stats["skipped"] += 1
        else:
            by_tid.setdefault(tid, []).append(game)
    if not by_tid:
        return
    try:
        urls = icon_urls(set(by_tid))
    except Exception as exc:
        stats["errors"].append(f"{system.code}: titledb: {exc}")
        return
    for tid, tid_games in by_tid.items():
        url = urls.get(tid)
        for game in tid_games:
            if url is None:
                stats["skipped"] += 1
                continue
            try:
                download_image(url, full_path(game.id))
                _make_thumb(game.id)
                Cover.objects.update_or_create(
                    game=game,
                    defaults={
                        "source": Cover.Source.TITLEDB,
                        "match_name": tid,
                        "score": 100.0,
                        "is_manual": False,
                    },
                )
                stats["matched"] += 1
            except Exception as exc:
                stats["errors"].append(f"{game.title}: {exc}")


def match_all() -> dict:
    ensure_dirs()
    stats = {"matched": 0, "skipped": 0, "errors": []}
    for system in System.objects.filter(code="switch"):
        match_switch(system, stats)
    for system in System.objects.exclude(thumbnail_repo=""):
        try:
            names = fetch_index(system.thumbnail_repo)
        except Exception as exc:
            stats["errors"].append(f"{system.code}: index: {exc}")
            continue
        for game in system.games.filter(cover__isnull=True):
            try:
                if match_game(game, names):
                    stats["matched"] += 1
                else:
                    stats["skipped"] += 1
            except Exception as exc:
                stats["errors"].append(f"{game.title}: {exc}")
    return stats
