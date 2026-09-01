from django.core.management.base import BaseCommand

from library.scanner.scan import run_scan


class Command(BaseCommand):
    help = "Scan the ROM library synchronously."

    def handle(self, *args, **options):
        run = run_scan()
        self.stdout.write(
            f"{run.status}: +{run.files_created} ~{run.files_updated} "
            f"-{run.files_deleted} files, errors: {len(run.errors)}"
        )
