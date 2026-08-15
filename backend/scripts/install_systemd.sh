#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-fuyao-backend}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVICE_TEMPLATE="$ROOT_DIR/backend/deploy/fuyao-backend.service.example"
SERVICE_TARGET="/etc/systemd/system/${SERVICE_NAME}.service"
SERVICE_USER="fuyao"
SHARED_DIR="/opt/fuyao-backend/shared"

if [[ ! -f "$SERVICE_TEMPLATE" ]]; then
  echo "missing service template: $SERVICE_TEMPLATE" >&2
  exit 1
fi

if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
  useradd --system --home-dir /nonexistent --shell /usr/sbin/nologin "$SERVICE_USER"
fi

install -d -o "$SERVICE_USER" -g "$SERVICE_USER" "$SHARED_DIR"
chown -R "$SERVICE_USER:$SERVICE_USER" "$SHARED_DIR"

cp "$SERVICE_TEMPLATE" "$SERVICE_TARGET"
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"
systemctl --no-pager --full status "$SERVICE_NAME"
