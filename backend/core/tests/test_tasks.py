import pytest

from core.tasks import ping


@pytest.mark.django_db
def test_ping_enqueues_and_runs_immediately():
    result = ping.enqueue()
    assert result.status.name == "SUCCESSFUL"
    assert result.return_value == "pong"
