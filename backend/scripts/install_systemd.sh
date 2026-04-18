#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-fuyao-backend}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVICE_TEMPLATE="$ROOT_DIR/backend/deploy/fuyao-backend.service.example"
SERVICE_TARGET="/etc/systemd/system/${SERVICE_NAME}.service"

if [[ ! -f "$SERVICE_TEMPLATE" ]]; then
  echo "missing service template: $SERVICE_TEMPLATE" >&2
  exit 1
fi

cp "$SERVICE_TEMPLATE" "$SERVICE_TARGET"
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"
systemctl --no-pager --full status "$SERVICE_NAME"
