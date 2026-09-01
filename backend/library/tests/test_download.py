import pytest
from django.test import override_settings
from rest_framework.test import APIClient

from library.models import Game, GameFile, System

CONTENT = bytes(range(256)) * 4  # 1024 bytes


@pytest.fixture
def gamefile(db, tmp_path):
    (tmp_path / "snes").mkdir()
    (tmp_path / "snes" / "Mario (USA).sfc").write_bytes(CONTENT)
    s = System.objects.create(code="snes", name="SNES", directory="snes")
    g = Game.objects.create(system=s, title="Mario", normalized_title="mario")
    gf = GameFile.objects.create(
        game=g, relative_path="snes/Mario (USA).sfc", size=1024, mtime_ns=1
    )
    return gf, tmp_path


def _get(client, gf, root, **headers):
    with override_settings(LIBRARY_ROOT=root):
        return client.get(f"/api/files/{gf.id}/download", **headers)


def test_full_download(auth_client, gamefile):
    gf, root = gamefile
    resp = _get(auth_client, gf, root)
    assert resp.status_code == 200
    assert resp["Accept-Ranges"] == "bytes"
    assert resp["Content-Length"] == "1024"
    assert 'filename="Mario (USA).sfc"' in resp["Content-Disposition"]
    assert b"".join(resp.streaming_content) == CONTENT


def test_range_resume(auth_client, gamefile):
    gf, root = gamefile
    resp = _get(auth_client, gf, root, HTTP_RANGE="bytes=1000-")
    assert resp.status_code == 206
    assert resp["Content-Range"] == "bytes 1000-1023/1024"
    assert b"".join(resp.streaming_content) == CONTENT[1000:]


def test_range_window(auth_client, gamefile):
    gf, root = gamefile
    resp = _get(auth_client, gf, root, HTTP_RANGE="bytes=0-99")
    assert resp.status_code == 206
    assert len(b"".join(resp.streaming_content)) == 100


def test_bad_range_416(auth_client, gamefile):
    gf, root = gamefile
    assert _get(auth_client, gf, root, HTTP_RANGE="bytes=99999-").status_code == 416
    assert _get(auth_client, gf, root, HTTP_RANGE="chunks=1-2").status_code == 416


def test_download_requires_auth(gamefile):
    gf, root = gamefile
    with override_settings(LIBRARY_ROOT=root):
        assert APIClient().get(f"/api/files/{gf.id}/download").status_code == 401


def test_symlink_escape_is_404(auth_client, gamefile, tmp_path):
    gf, root = gamefile
    outside = tmp_path.parent / "poza.bin"
    outside.write_bytes(b"tajne")
    (root / "snes" / "Zly.sfc").symlink_to(outside)
    gf2 = GameFile.objects.create(
        game=gf.game, relative_path="snes/Zly.sfc", size=5, mtime_ns=1
    )
    assert _get(auth_client, gf2, root).status_code == 404


def test_stream_stops_when_file_shrinks_mid_transfer(auth_client, gamefile):
    # StreamingHttpResponse is lazy — the file is read on iteration; this covers
    # the `if not chunk` branch in _iter_file (without it the loop would hang).
    gf, root = gamefile
    resp = _get(auth_client, gf, root)
    (root / "snes" / "Mario (USA).sfc").write_bytes(CONTENT[:10])
    assert b"".join(resp.streaming_content) == CONTENT[:10]
