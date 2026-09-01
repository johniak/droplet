from pathlib import Path

from django.conf import settings


def test_paths_are_pathlib():
    assert isinstance(settings.LIBRARY_ROOT, Path)
    assert isinstance(settings.DATA_DIR, Path)


def test_drf_defaults_require_auth():
    assert (
        "rest_framework.permissions.IsAuthenticated"
        in settings.REST_FRAMEWORK["DEFAULT_PERMISSION_CLASSES"]
    )


def test_root_urlconf_loads():
    from django.urls import reverse

    assert reverse("admin:index") == "/admin/"
