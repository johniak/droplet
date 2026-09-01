import os

from django.contrib.auth.models import User
from django.core.management.base import BaseCommand, CommandError


class Command(BaseCommand):
    help = "Create the single Droplet user from env (idempotent)."

    def handle(self, *args, **options):
        username = os.environ.get("DROPLET_ADMIN_USER")
        password = os.environ.get("DROPLET_ADMIN_PASSWORD")
        if not username or not password:
            raise CommandError("Set DROPLET_ADMIN_USER and DROPLET_ADMIN_PASSWORD")
        if User.objects.filter(username=username).exists():
            self.stdout.write("User already exists, skipping")
            return
        User.objects.create_superuser(username=username, password=password)
        self.stdout.write(self.style.SUCCESS(f"Created user {username}"))
