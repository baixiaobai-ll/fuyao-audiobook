#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEFAULT_SHARED_ENV="/opt/fuyao-backend/shared/backend.env"

if [[ -z "${FUYAO_ENV_FILE:-}" && -f "$DEFAULT_SHARED_ENV" ]]; then
  ENV_FILE="$DEFAULT_SHARED_ENV"
else
  ENV_FILE="${FUYAO_ENV_FILE:-$ROOT_DIR/backend/.env}"
fi

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

cd "$ROOT_DIR"
exec python3 -m backend.main serve \
  --host "${FUYAO_BACKEND_HOST:-127.0.0.1}" \
  --port "${FUYAO_BACKEND_PORT:-8787}"
