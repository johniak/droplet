from django.contrib import admin

from .models import Game, GameFile, ScanRun, System

admin.site.register(System)
admin.site.register(Game)
admin.site.register(GameFile)
admin.site.register(ScanRun)
