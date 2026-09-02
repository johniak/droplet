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
