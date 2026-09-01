from django.conf import settings
from django.tasks import task

from .models import ScanRun
from .scanner.scan import run_scan


@task()
def scan_library() -> int:
    run = run_scan()
    if run.status == ScanRun.Status.SUCCESS and settings.COVERS_AUTO_MATCH:
        from covers.tasks import match_covers

        match_covers.enqueue()
    return run.pk
