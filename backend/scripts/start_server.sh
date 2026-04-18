#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${FUYAO_ENV_FILE:-$ROOT_DIR/backend/.env}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

cd "$ROOT_DIR"
exec python3 -m backend.main serve \
  --host "${FUYAO_BACKEND_HOST:-0.0.0.0}" \
  --port "${FUYAO_BACKEND_PORT:-8787}"
