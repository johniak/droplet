import pytest
from django.core.management import call_command
from django.test import override_settings
from rest_framework.test import APIClient

from library.models import ScanRun


@pytest.mark.django_db
def test_scan_command_runs(tmp_path, capsys):
    with override_settings(LIBRARY_ROOT=tmp_path):
        call_command("scan")
    assert ScanRun.objects.count() == 1


@pytest.mark.django_db
def test_scan_endpoint_enqueues(auth_client, tmp_path):
    with override_settings(LIBRARY_ROOT=tmp_path):
        resp = auth_client.post("/api/scan/")
    assert resp.status_code == 202
    assert ScanRun.objects.count() == 1


@pytest.mark.django_db
def test_scan_endpoint_requires_auth():
    assert APIClient().post("/api/scan/").status_code == 401
