import pytest
from django.conf import settings

from covers.models import Cover
from covers.paths import ensure_dirs, full_path, index_path, thumb_path
from library.models import Game, System


@pytest.mark.django_db
def test_cover_one_to_one():
    s = System.objects.create(code="snes", name="SNES", directory="snes")
    g = Game.objects.create(system=s, title="Mario", normalized_title="mario")
    Cover.objects.create(
        game=g, source=Cover.Source.LIBRETRO, match_name="Mario", score=100
    )
    assert g.cover.match_name == "Mario"


def test_paths_under_data_dir():
    assert str(full_path(7)).startswith(str(settings.DATA_DIR))
    assert full_path(7).name == "7.png"
    assert thumb_path(7).parent.name == "thumb"


def test_index_path_and_ensure_dirs(tmp_path, settings):
    settings.DATA_DIR = tmp_path
    assert index_path("Sony_-_PlayStation").name == "Sony_-_PlayStation.json"
    ensure_dirs()
    assert {p.name for p in (tmp_path / "covers").iterdir()} == {
        "full",
        "thumb",
        "index",
    }


@pytest.mark.django_db
def test_cover_str():
    s = System.objects.create(code="snes", name="SNES", directory="snes")
    g = Game.objects.create(system=s, title="Mario", normalized_title="mario")
    cover = Cover.objects.create(
        game=g, source=Cover.Source.LIBRETRO, match_name="Mario"
    )
    assert str(cover) == f"Cover({g.pk}, Mario)"
