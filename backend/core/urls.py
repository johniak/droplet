from django.urls import path

from . import views

urlpatterns = [
    path("health/", views.health, name="health"),
    path("auth/token/", views.ObtainTokenView.as_view(), name="obtain-token"),
    path("me/", views.me, name="me"),
]
