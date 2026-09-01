import pytest
from django.db import IntegrityError

from library.models import Game, GameFile, ScanRun, System


@pytest.mark.django_db
def test_game_unique_per_system():
    s = System.objects.create(code="snes", name="SNES", directory="snes")
    Game.objects.create(system=s, title="Mario", normalized_title="mario")
    with pytest.raises(IntegrityError):
        Game.objects.create(system=s, title="Mario 2", normalized_title="mario")


@pytest.mark.django_db
def test_gamefile_path_unique():
    s = System.objects.create(code="snes", name="SNES", directory="snes")
    g = Game.objects.create(system=s, title="Mario", normalized_title="mario")
    GameFile.objects.create(game=g, relative_path="snes/mario.sfc", size=1, mtime_ns=1)
    with pytest.raises(IntegrityError):
        GameFile.objects.create(
            game=g, relative_path="snes/mario.sfc", size=2, mtime_ns=2
        )


@pytest.mark.django_db
def test_string_representations():
    s = System.objects.create(code="snes", name="SNES", directory="snes")
    g = Game.objects.create(system=s, title="Mario", normalized_title="mario")
    f = GameFile.objects.create(
        game=g, relative_path="snes/mario.sfc", size=1, mtime_ns=1
    )
    run = ScanRun.objects.create()
    assert str(s) == "SNES"
    assert str(g) == "Mario"
    assert str(f) == "snes/mario.sfc"
    assert str(run) == f"ScanRun {run.pk} (running)"
