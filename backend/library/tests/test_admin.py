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
