#!/bin/sh
# Generate runtime config from environment variables.
# This runs at container startup so the image stays environment-agnostic.
cat <<EOF > /usr/share/nginx/html/config.js
window.__CONFIG__ = {
  VITE_ENTRA_CLIENT_ID: "${VITE_ENTRA_CLIENT_ID:-}",
  VITE_ENTRA_TENANT_ID: "${VITE_ENTRA_TENANT_ID:-}",
  VITE_TASKS_API_SCOPE: "${VITE_TASKS_API_SCOPE:-}"
};
EOF
exec "$@"
