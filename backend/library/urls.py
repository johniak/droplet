from django.urls import path

from . import api

urlpatterns = [
    path("scan/", api.trigger_scan, name="trigger-scan"),
]
