import pytest


@pytest.mark.django_db
def test_health_requires_no_auth(client):
    resp = client.get("/api/health/")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok", "api_version": 1}
