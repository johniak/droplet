import pytest
from django.contrib.auth.models import User
from django.core.management import CommandError, call_command


@pytest.mark.django_db
def test_creates_superuser_from_env(monkeypatch):
    monkeypatch.setenv("DROPLET_ADMIN_USER", "jan")
    monkeypatch.setenv("DROPLET_ADMIN_PASSWORD", "sekret123")
    call_command("createinitialuser")
    user = User.objects.get(username="jan")
    assert user.is_superuser and user.check_password("sekret123")


@pytest.mark.django_db
def test_idempotent(monkeypatch):
    monkeypatch.setenv("DROPLET_ADMIN_USER", "jan")
    monkeypatch.setenv("DROPLET_ADMIN_PASSWORD", "sekret123")
    call_command("createinitialuser")
    call_command("createinitialuser")
    assert User.objects.count() == 1


@pytest.mark.django_db
def test_missing_env_raises(monkeypatch):
    monkeypatch.delenv("DROPLET_ADMIN_USER", raising=False)
    with pytest.raises(CommandError):
        call_command("createinitialuser")
