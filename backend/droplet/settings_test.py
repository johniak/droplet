from .settings import *  # noqa: F403

DATA_DIR = BASE_DIR / ".test-data"  # noqa: F405
DATA_DIR.mkdir(exist_ok=True)
DATABASES["default"]["NAME"] = ":memory:"  # noqa: F405
TASKS = {"default": {"BACKEND": "django.tasks.backends.immediate.ImmediateBackend"}}
LIBRARY_ROOT = BASE_DIR / ".test-library"  # noqa: F405
