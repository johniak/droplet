#!/bin/sh
set -e
if [ "$1" = "web" ]; then
  python manage.py migrate --noinput
  python manage.py createinitialuser
  python manage.py collectstatic --noinput
  # gthread: pobieranie plików to długie strumienie — przy workerach sync dwa
  # równoległe pobierania blokują całe API, a transfer dłuższy niż --timeout
  # jest ubijany. Wątki obsługują wiele strumieni naraz, a timeout dotyczy
  # tylko bezczynności workera.
  exec gunicorn droplet.wsgi:application --bind 0.0.0.0:8000 \
    --worker-class gthread --workers 2 --threads 8 --timeout 120 --keep-alive 30
elif [ "$1" = "worker" ]; then
  exec python manage.py db_worker
else
  exec "$@"
fi
