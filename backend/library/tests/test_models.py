import pytest
from django.db import IntegrityError

from library.models import Game, GameFile, LooseFile, ScanRun, System


@pytest.mark.django_db
def test_two_games_may_share_title_but_not_folder():
    snes = System.objects.create(code="snes", name="SNES", directory="snes")
    Game.objects.create(system=snes, folder="snes/Zelda (USA)", title="Zelda",
                        normalized_title="zelda")
    Game.objects.create(system=snes, folder="snes/Zelda (EUR)", title="Zelda",
                        normalized_title="zelda")
    with pytest.raises(IntegrityError):
        Game.objects.create(system=snes, folder="snes/Zelda (USA)", title="Zelda 2",
                            normalized_title="zelda 2")


@pytest.mark.django_db
def test_empty_folder_is_allowed_many_times():
    snes = System.objects.create(code="snes", name="SNES", directory="snes")
    Game.objects.create(system=snes, title="A", normalized_title="a")
    Game.objects.create(system=snes, title="B", normalized_title="b")
    assert Game.objects.filter(folder="").count() == 2


@pytest.mark.django_db
def test_loose_file_str_and_scanrun_counter():
    snes = System.objects.create(code="snes", name="SNES", directory="snes")
    lf = LooseFile.objects.create(system=snes, relative_path="snes/x.sfc", size=3)
    assert str(lf) == "snes/x.sfc"
    assert ScanRun.objects.create().loose_files == 0


@pytest.mark.django_db
def test_fill_folder_derives_from_first_file():
    from importlib import import_module

    from django.apps import apps as global_apps

    mod = import_module("library.migrations.0002_folders")
    snes = System.objects.create(code="snes", name="SNES", directory="snes")
    g = Game.objects.create(system=snes, title="Mario", normalized_title="mario")
    GameFile.objects.create(game=g, relative_path="snes/Mario (USA)/m.sfc", size=1, mtime_ns=1)
    loose = Game.objects.create(system=snes, title="Loose", normalized_title="loose")
    GameFile.objects.create(game=loose, relative_path="snes/l.sfc", size=1, mtime_ns=1)
    mod.fill_folder(global_apps, None)
    g.refresh_from_db()
    loose.refresh_from_db()
    assert g.folder == "snes/Mario (USA)"
    assert loose.folder == ""


@pytest.mark.django_db
def test_fill_folder_trims_deeper_paths_to_the_game_folder():
    """psx/FF7/disc1/… to nadal gra „psx/FF7" — tak samo grupuje skaner."""
    from importlib import import_module

    from django.apps import apps as global_apps

    mod = import_module("library.migrations.0002_folders")
    psx = System.objects.create(code="psx", name="PSX", directory="psx")
    g = Game.objects.create(system=psx, title="FF7", normalized_title="ff7")
    GameFile.objects.create(
        game=g, relative_path="psx/FF7/disc1/FF7 (Disc 1).bin", size=1, mtime_ns=1
    )
    mod.fill_folder(global_apps, None)
    g.refresh_from_db()
    assert g.folder == "psx/FF7"


@pytest.mark.django_db
def test_fill_folder_gives_a_shared_folder_to_the_first_game_only():
    """Folder jest unikalny — dwie stare gry w jednym katalogu nie mogą go dzielić."""
    from importlib import import_module

    from django.apps import apps as global_apps

    mod = import_module("library.migrations.0002_folders")
    psx = System.objects.create(code="psx", name="PSX", directory="psx")
    first = Game.objects.create(system=psx, title="Disc 1", normalized_title="disc 1")
    GameFile.objects.create(
        game=first, relative_path="psx/FF7/a.bin", size=1, mtime_ns=1
    )
    second = Game.objects.create(system=psx, title="Disc 2", normalized_title="disc 2")
    GameFile.objects.create(
        game=second, relative_path="psx/FF7/b.bin", size=1, mtime_ns=1
    )
    mod.fill_folder(global_apps, None)
    first.refresh_from_db()
    second.refresh_from_db()
    assert (first.folder, second.folder) == ("psx/FF7", "")


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
