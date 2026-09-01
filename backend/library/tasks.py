from django.tasks import task

from .scanner.scan import run_scan


@task()
def scan_library() -> int:
    run = run_scan()
    return run.pk
