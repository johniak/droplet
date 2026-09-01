import io

import pytest
import responses
from PIL import Image

from covers.models import Cover
from covers.service import match_all
from library.models import Game, System


def _png_bytes():
    buf = io.BytesIO()
    Image.new("RGB", (100, 140), "blue").save(buf, format="PNG")
    return buf.getvalue()


@responses.activate
@pytest.mark.django_db
def test_manual_cover_survives_rematch(settings, tmp_path):
    settings.DATA_DIR = tmp_path
    s = System.objects.create(
        code="snes", name="SNES", directory="snes", thumbnail_repo="R"
    )
    g = Game.objects.create(system=s, title="Mario", normalized_title="mario")
    Cover.objects.create(
        game=g, source=Cover.Source.MANUAL, is_manual=True, match_name="Reczny Wybor"
    )
    responses.get(
        "https://api.github.com/repos/libretro-thumbnails/R/git/trees/master",
        json={"tree": [{"path": "Named_Boxarts/Mario (USA).png", "type": "blob"}]},
    )
    match_all()
    g.refresh_from_db()
    assert g.cover.match_name == "Reczny Wybor"
    assert g.cover.is_manual is True


@pytest.fixture
def admin_client_(client, db):
    from django.contrib.auth.models import User

    User.objects.create_superuser(username="root", password="root123")
    client.login(username="root", password="root123")
    return client


@pytest.mark.django_db
def test_cover_admin_list_renders(admin_client_):
    assert admin_client_.get("/admin/covers/cover/").status_code == 200


@pytest.mark.django_db
def test_has_cover_filter(admin_client_, settings, tmp_path):
    settings.DATA_DIR = tmp_path
    s = System.objects.create(code="snes", name="SNES", directory="snes")
    mario = Game.objects.create(system=s, title="MarioX", normalized_title="mariox")
    Game.objects.create(system=s, title="ZeldaX", normalized_title="zeldax")
    Cover.objects.create(game=mario, source=Cover.Source.LIBRETRO, match_name="m")
    yes = admin_client_.get("/admin/library/game/?has_cover=yes").content
    no = admin_client_.get("/admin/library/game/?has_cover=no").content
    assert b"MarioX" in yes and b"ZeldaX" not in yes
    assert b"ZeldaX" in no and b"MarioX" not in no
    assert admin_client_.get("/admin/library/game/").status_code == 200


@pytest.mark.django_db
def test_show_cover_candidates_action(admin_client_, settings, tmp_path):
    import json
    import time

    from covers.paths import index_path

    settings.DATA_DIR = tmp_path
    s = System.objects.create(
        code="snes", name="SNES", directory="snes", thumbnail_repo="R"
    )
    g = Game.objects.create(system=s, title="Mario", normalized_title="mario")
    p = index_path("R")
    p.parent.mkdir(parents=True)
    p.write_text(
        json.dumps({"fetched_at": time.time(), "names": ["Mario (USA)", "Zelda (USA)"]})
    )
    resp = admin_client_.post(
        "/admin/library/game/",
        {"action": "show_cover_candidates", "_selected_action": [g.pk]},
        follow=True,
    )
    assert b"Mario (USA) (100)" in resp.content


@pytest.mark.django_db
def test_cover_upload_marks_manual(admin_client_, settings, tmp_path):
    from django.core.files.uploadedfile import SimpleUploadedFile

    from covers.paths import full_path, thumb_path

    settings.DATA_DIR = tmp_path
    s = System.objects.create(code="snes", name="SNES", directory="snes")
    g = Game.objects.create(system=s, title="Mario", normalized_title="mario")
    cover = Cover.objects.create(
        game=g, source=Cover.Source.LIBRETRO, match_name="auto"
    )
    upload = SimpleUploadedFile("c.png", _png_bytes(), content_type="image/png")
    resp = admin_client_.post(
        f"/admin/covers/cover/{cover.pk}/change/",
        {"match_name": "auto", "upload": upload, "_save": "Save"},
        follow=True,
    )
    assert resp.status_code == 200
    cover.refresh_from_db()
    assert cover.is_manual is True and cover.source == Cover.Source.MANUAL
    assert full_path(g.id).exists() and thumb_path(g.id).exists()


@pytest.mark.django_db
def test_cover_change_without_upload_keeps_source(admin_client_, settings, tmp_path):
    settings.DATA_DIR = tmp_path
    s = System.objects.create(code="snes", name="SNES", directory="snes")
    g = Game.objects.create(system=s, title="Mario", normalized_title="mario")
    cover = Cover.objects.create(
        game=g, source=Cover.Source.LIBRETRO, match_name="auto"
    )
    admin_client_.post(
        f"/admin/covers/cover/{cover.pk}/change/",
        {"match_name": "nowa", "_save": "Save"},
        follow=True,
    )
    cover.refresh_from_db()
    assert cover.match_name == "nowa" and cover.source == Cover.Source.LIBRETRO


@responses.activate
@pytest.mark.django_db
def test_refetch_action_downloads_and_locks(admin_client_, settings, tmp_path):
    from covers.paths import thumb_path

    settings.DATA_DIR = tmp_path
    s = System.objects.create(
        code="snes", name="SNES", directory="snes", thumbnail_repo="R"
    )
    g = Game.objects.create(system=s, title="Mario", normalized_title="mario")
    cover = Cover.objects.create(
        game=g, source=Cover.Source.LIBRETRO, match_name="Mario (USA)"
    )
    responses.get(
        "https://raw.githubusercontent.com/libretro-thumbnails/R"
        "/master/Named_Boxarts/Mario%20%28USA%29.png",
        body=_png_bytes(),
    )
    resp = admin_client_.post(
        "/admin/covers/cover/",
        {"action": "refetch_from_match_name", "_selected_action": [cover.pk]},
        follow=True,
    )
    assert resp.status_code == 200
    cover.refresh_from_db()
    assert cover.is_manual is True and cover.source == Cover.Source.MANUAL
    assert thumb_path(g.id).exists()
