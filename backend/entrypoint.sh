#!/bin/sh
set -e
if [ "$1" = "web" ]; then
  python manage.py migrate --noinput
  python manage.py createinitialuser
  python manage.py collectstatic --noinput
  exec gunicorn droplet.wsgi:application --bind 0.0.0.0:8000 --workers 2 --timeout 120
elif [ "$1" = "worker" ]; then
  exec python manage.py db_worker
else
  exec "$@"
fi
