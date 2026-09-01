import pytest
import requests


def test_real_http_is_blocked_in_tests():
    with pytest.raises(RuntimeError, match="Sieć zablokowana"):
        requests.get("https://example.com", timeout=1)


def test_auto_covers_default_on(settings):
    assert settings.COVERS_AUTO_MATCH is True
