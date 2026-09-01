import pytest
from django.test import override_settings

from library.models import Game, GameFile, ScanRun, System
from library.scanner.scan import run_scan


@pytest.fixture
def library(tmp_path):
    d = tmp_path / "snes"
    d.mkdir()
    (d / "Super Mario World (USA).sfc").write_bytes(b"a" * 10)
    (d / "F-Zero (USA).sfc").write_bytes(b"b" * 20)
    return tmp_path


@pytest.mark.django_db
def test_initial_scan_creates_everything(library):
    with override_settings(LIBRARY_ROOT=library):
        run = run_scan()
    assert run.status == ScanRun.Status.SUCCESS
    assert System.objects.get(code="snes")
    assert Game.objects.count() == 2
    assert GameFile.objects.count() == 2
    assert run.files_created == 2


@pytest.mark.django_db
def test_rescan_is_idempotent(library):
    with override_settings(LIBRARY_ROOT=library):
        run_scan()
        run2 = run_scan()
    assert (run2.files_created, run2.files_updated, run2.files_deleted) == (0, 0, 0)


@pytest.mark.django_db
def test_deleted_file_removes_game(library):
    with override_settings(LIBRARY_ROOT=library):
        run_scan()
        (library / "snes" / "F-Zero (USA).sfc").unlink()
        run2 = run_scan()
    assert run2.files_deleted == 1
    assert not Game.objects.filter(title="F-Zero").exists()


@pytest.mark.django_db
def test_modified_file_updates_size(library):
    with override_settings(LIBRARY_ROOT=library):
        run_scan()
        (library / "snes" / "F-Zero (USA).sfc").write_bytes(b"c" * 99)
        run2 = run_scan()
    assert run2.files_updated == 1
    assert GameFile.objects.get(relative_path__contains="F-Zero").size == 99


@pytest.mark.django_db
def test_unknown_directory_flagged(tmp_path):
    (tmp_path / "Dziwny Folder").mkdir()
    (tmp_path / "Dziwny Folder" / "x.rom").write_bytes(b"x")
    with override_settings(LIBRARY_ROOT=tmp_path):
        run_scan()
    assert System.objects.get(directory="Dziwny Folder").needs_config is True


@pytest.mark.django_db
def test_switch_family_with_and_without_title_id_is_one_game(tmp_path):
    d = tmp_path / "switch"
    d.mkdir()
    (d / "Celeste [01002B30028F6000][v0].nsp").write_bytes(b"a")
    (d / "Celeste (UPD) (v1.2.6).nsp").write_bytes(b"b")
    with override_settings(LIBRARY_ROOT=tmp_path):
        run = run_scan()
    assert run.status == ScanRun.Status.SUCCESS
    game = Game.objects.get(system__code="switch")
    assert game.switch_title_prefix == "01002B30028F"
    assert sorted(game.files.values_list("role", flat=True)) == ["base", "update"]


@pytest.mark.django_db
def test_missing_library_root_marks_run_failed(tmp_path):
    with override_settings(LIBRARY_ROOT=tmp_path / "nie-ma"):
        run = run_scan()
    assert run.status == ScanRun.Status.FAILED
    assert run.errors and run.finished_at is not None


@pytest.mark.django_db
def test_system_error_is_recorded_and_scan_continues(library, monkeypatch):
    import library.scanner.scan as scan_module

    def boom(*args, **kwargs):
        raise OSError("dysk odpięty")

    monkeypatch.setattr(scan_module, "group_system_dir", boom)
    with override_settings(LIBRARY_ROOT=library):
        run = run_scan()
    assert run.status == ScanRun.Status.SUCCESS
    assert any("dysk odpięty" in e for e in run.errors)


@pytest.mark.django_db
def test_switch_rescan_matches_existing_game_by_title_prefix(tmp_path):
    d = tmp_path / "switch"
    d.mkdir()
    (d / "Celeste [01002B30028F6000][v0].nsp").write_bytes(b"a")
    with override_settings(LIBRARY_ROOT=tmp_path):
        run_scan()
        run2 = run_scan()
    assert run2.games_created == 0
    assert Game.objects.filter(switch_title_prefix="01002B30028F").count() == 1
