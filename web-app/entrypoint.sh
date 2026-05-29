#!/bin/sh
# Generate runtime nginx config with the Tasks API upstream URL.
sed -i "s|TASKS_API_UPSTREAM|${TASKS_API_URL:-http://localhost:5223}|g" /etc/nginx/conf.d/default.conf
exec "$@"
