import pytest
from django.test import override_settings

from library.models import Game, GameFile, LooseFile, ScanRun, System
from library.scanner.scan import run_scan


def _write(p, content=b"x"):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(content)


@pytest.fixture
def library(tmp_path):
    _write(tmp_path / "snes" / "Super Mario World (USA)" / "Super Mario World (USA).sfc", b"a" * 10)
    _write(tmp_path / "snes" / "F-Zero (USA)" / "F-Zero (USA).sfc", b"b" * 20)
    _write(tmp_path / "snes" / "Loose (USA).sfc", b"c" * 5)
    return tmp_path


@pytest.mark.django_db
def test_initial_scan_creates_games_and_loose(library):
    with override_settings(LIBRARY_ROOT=library):
        run = run_scan()
    assert run.status == ScanRun.Status.SUCCESS
    assert Game.objects.count() == 2
    assert Game.objects.get(title="F-Zero").folder == "snes/F-Zero (USA)"
    assert GameFile.objects.count() == 2
    assert LooseFile.objects.get().relative_path == "snes/Loose (USA).sfc"
    assert run.loose_files == 1 and run.files_created == 2


@pytest.mark.django_db
def test_rescan_is_idempotent(library):
    with override_settings(LIBRARY_ROOT=library):
        run_scan()
        run2 = run_scan()
    assert (run2.files_created, run2.files_updated, run2.files_deleted) == (0, 0, 0)
    assert LooseFile.objects.count() == 1 and run2.loose_files == 1


@pytest.mark.django_db
def test_loose_file_moved_into_folder_becomes_game(library):
    with override_settings(LIBRARY_ROOT=library):
        run_scan()
        src = library / "snes" / "Loose (USA).sfc"
        _write(library / "snes" / "Loose (USA)" / "Loose (USA).sfc", src.read_bytes())
        src.unlink()
        run2 = run_scan()
    assert LooseFile.objects.count() == 0
    assert Game.objects.filter(folder="snes/Loose (USA)").exists()
    assert run2.games_created == 1


@pytest.mark.django_db
def test_renamed_folder_is_new_game_and_old_one_goes(library):
    with override_settings(LIBRARY_ROOT=library):
        run_scan()
        (library / "snes" / "F-Zero (USA)").rename(library / "snes" / "F-Zero (EUR)")
        run2 = run_scan()
    assert not Game.objects.filter(folder="snes/F-Zero (USA)").exists()
    assert Game.objects.get(folder="snes/F-Zero (EUR)").title == "F-Zero"
    assert run2.files_deleted == 1 and run2.files_created == 1


@pytest.mark.django_db
def test_deleted_folder_removes_game(library):
    import shutil
    with override_settings(LIBRARY_ROOT=library):
        run_scan()
        shutil.rmtree(library / "snes" / "F-Zero (USA)")
        run2 = run_scan()
    assert run2.files_deleted == 1
    assert not Game.objects.filter(title="F-Zero").exists()


@pytest.mark.django_db
def test_modified_file_updates_size(library):
    with override_settings(LIBRARY_ROOT=library):
        run_scan()
        (library / "snes" / "F-Zero (USA)" / "F-Zero (USA).sfc").write_bytes(b"c" * 99)
        run2 = run_scan()
    assert run2.files_updated == 1
    assert GameFile.objects.get(relative_path__endswith="F-Zero (USA).sfc").size == 99


@pytest.mark.django_db
def test_legacy_game_without_folder_is_removed_on_first_scan(library):
    snes = System.objects.create(code="snes", name="SNES", directory="snes")
    legacy = Game.objects.create(system=snes, title="Old", normalized_title="old")
    GameFile.objects.create(game=legacy, relative_path="snes/Old.sfc", size=1, mtime_ns=1)
    with override_settings(LIBRARY_ROOT=library):
        run_scan()
    assert not Game.objects.filter(title="Old").exists()


@pytest.mark.django_db
def test_two_folders_same_title_are_two_games(tmp_path):
    _write(tmp_path / "snes" / "Zelda (USA)" / "z.sfc")
    _write(tmp_path / "snes" / "Zelda (EUR)" / "z.sfc")
    with override_settings(LIBRARY_ROOT=tmp_path):
        run = run_scan()
    assert run.status == ScanRun.Status.SUCCESS
    assert Game.objects.filter(normalized_title="zelda").count() == 2


@pytest.mark.django_db
def test_missing_library_root_marks_run_failed(tmp_path):
    with override_settings(LIBRARY_ROOT=tmp_path / "nope"):
        run = run_scan()
    assert run.status == ScanRun.Status.FAILED and run.errors


@pytest.mark.django_db
def test_system_error_is_recorded_and_scan_continues(library, monkeypatch):
    def boom(*a, **k):
        raise OSError("disk")
    monkeypatch.setattr("library.scanner.scan.group_system_dir", boom)
    with override_settings(LIBRARY_ROOT=library):
        run = run_scan()
    assert run.status == ScanRun.Status.SUCCESS and "snes: disk" in run.errors


@pytest.mark.django_db
def test_switch_prefix_is_updated_when_base_file_appears(tmp_path):
    _write(tmp_path / "switch" / "Game" / "Game [UPD][0100633007D48800][v1].nsp")
    with override_settings(LIBRARY_ROOT=tmp_path):
        run_scan()
        _write(tmp_path / "switch" / "Game" / "Game [0100633007D40000].nsp")
        run_scan()
    game = Game.objects.get(folder="switch/Game")
    assert game.switch_title_prefix == "0100633007D4"


@pytest.mark.django_db
def test_loose_file_size_change_is_updated(library):
    with override_settings(LIBRARY_ROOT=library):
        run_scan()
        (library / "snes" / "Loose (USA).sfc").write_bytes(b"z" * 99)
        run_scan()
    assert LooseFile.objects.get().size == 99


@pytest.mark.django_db
def test_unknown_directory_flagged(tmp_path):
    (tmp_path / "Dziwny Folder").mkdir()
    (tmp_path / "Dziwny Folder" / "x.rom").write_bytes(b"x")
    with override_settings(LIBRARY_ROOT=tmp_path):
        run_scan()
    assert System.objects.get(directory="Dziwny Folder").needs_config is True
