from django.tasks import task

from .service import match_all


@task()
def match_covers() -> dict:
    return match_all()
