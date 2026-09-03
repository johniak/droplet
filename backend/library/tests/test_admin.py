import pytest
from django.contrib.auth.models import User


@pytest.fixture
def admin_client_(client, db):
    User.objects.create_superuser(username="root", password="root123")
    client.login(username="root", password="root123")
    return client


@pytest.mark.django_db
@pytest.mark.parametrize(
    "url",
    [
        "/admin/library/system/",
        "/admin/library/game/",
        "/admin/library/gamefile/",
        "/admin/library/scanrun/",
    ],
)
def test_admin_pages_render(admin_client_, url):
    assert admin_client_.get(url).status_code == 200


@pytest.mark.django_db
def test_game_list_shows_file_count(admin_client_):
    from library.models import Game, GameFile, System

    s = System.objects.create(code="snes", name="SNES", directory="snes")
    g = Game.objects.create(system=s, title="Mario", normalized_title="mario")
    GameFile.objects.create(game=g, relative_path="snes/m.sfc", size=1, mtime_ns=1)
    resp = admin_client_.get("/admin/library/game/")
    assert resp.status_code == 200
    assert b"Mario" in resp.content


@pytest.mark.django_db
def test_run_scan_action_enqueues(admin_client_, tmp_path):
    from django.test import override_settings

    from library.models import ScanRun

    old = ScanRun.objects.create()
    with override_settings(LIBRARY_ROOT=tmp_path):
        resp = admin_client_.post(
            "/admin/library/scanrun/",
            {"action": "run_scan_action", "_selected_action": [old.pk]},
            follow=True,
        )
    assert resp.status_code == 200
    assert ScanRun.objects.count() == 2


@pytest.mark.django_db
def test_loose_file_admin_lists_and_filters(admin_client_):
    from library.models import LooseFile, System

    snes = System.objects.create(code="snes", name="SNES", directory="snes")
    psx = System.objects.create(code="psx", name="PSX", directory="psx")
    LooseFile.objects.create(system=snes, relative_path="snes/a.sfc", size=1)
    LooseFile.objects.create(system=psx, relative_path="psx/b.bin", size=2)
    page = admin_client_.get("/admin/library/loosefile/")
    assert page.status_code == 200
    assert b"snes/a.sfc" in page.content and b"psx/b.bin" in page.content
    filtered = admin_client_.get(f"/admin/library/loosefile/?system__id__exact={snes.pk}")
    assert b"snes/a.sfc" in filtered.content and b"psx/b.bin" not in filtered.content
    assert admin_client_.get("/admin/library/loosefile/add/").status_code == 403


@pytest.mark.django_db
def test_system_admin_shows_loose_count(admin_client_):
    from library.models import LooseFile, System

    snes = System.objects.create(code="snes", name="SNES", directory="snes")
    LooseFile.objects.create(system=snes, relative_path="snes/a.sfc", size=1)
    page = admin_client_.get("/admin/library/system/")
    assert page.status_code == 200
    assert b">1<" in page.content  # kolumna „luzem"


@pytest.mark.django_db
def test_scanrun_admin_shows_loose_files(admin_client_):
    from library.models import ScanRun

    ScanRun.objects.create(loose_files=4, status=ScanRun.Status.SUCCESS)
    page = admin_client_.get("/admin/library/scanrun/")
    assert b">4<" in page.content


@pytest.mark.django_db
def test_loose_file_admin_refuses_edits_and_deletes(admin_client_):
    """Wiersze są lustrem skanu — nie ma czego ręcznie zmieniać ani kasować."""
    from library.admin import LooseFileAdmin
    from library.models import LooseFile, System

    snes = System.objects.create(code="snes", name="SNES", directory="snes")
    lf = LooseFile.objects.create(system=snes, relative_path="snes/a.sfc", size=1)
    assert admin_client_.post(f"/admin/library/loosefile/{lf.pk}/change/", {}).status_code == 403
    assert admin_client_.get(f"/admin/library/loosefile/{lf.pk}/delete/").status_code == 403
    assert LooseFileAdmin.has_change_permission(None, None, lf) is False
    assert LooseFileAdmin.has_delete_permission(None, None, lf) is False


@pytest.mark.django_db
def test_loose_file_hint_distinguishes_unpacked_mods():
    from library.admin import LooseFileAdmin
    from library.models import LooseFile, System

    system = System.objects.create(code="switch", name="Switch")
    a = LooseFile.objects.create(system=system, relative_path="switch/HK/mods/Unpacked/", size=1)
    b = LooseFile.objects.create(system=system, relative_path="switch/loose.nsp", size=1)
    admin_obj = LooseFileAdmin(LooseFile, None)
    assert admin_obj.hint(a).startswith("rozpakowany mod")
    assert admin_obj.hint(b) == "przenieś do katalogu gry"
    c = LooseFile.objects.create(system=system, relative_path="switch/Orphan/mods/skin.zip", size=1)
    assert admin_obj.hint(c).startswith("mod bez gry")


@pytest.mark.django_db
def test_scan_now_button_works_with_empty_list(admin_client_, monkeypatch):
    from library import admin as library_admin

    calls = []

    class FakeTask:
        def enqueue(self):
            calls.append(1)

    monkeypatch.setattr(library_admin, "scan_library", FakeTask())
    page = admin_client_.get("/admin/library/scanrun/")
    assert b"Skanuj teraz" in page.content
    assert b"/admin/library/scanrun/scan-now/" in page.content
    resp = admin_client_.post("/admin/library/scanrun/scan-now/")
    assert resp.status_code == 302 and resp.url == "/admin/library/scanrun/"
    assert calls == [1]
    # GET nie odpala skanu
    assert admin_client_.get("/admin/library/scanrun/scan-now/").status_code == 405
    assert calls == [1]
