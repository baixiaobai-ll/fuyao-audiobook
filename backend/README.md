# Fuyao Backend

This directory contains the minimal production-ready backend loop for:

- One-click login mobile exchange/login-register
- SMS verify-code fallback login
- Activation code redeem
- Permission status lookup
- Legacy usage consume and rollback compatibility

## Stack

- Python 3.9+
- Standard library HTTP server
- SQLite
- Aliyun PNVS one-click login API

No third-party package is required.

## Files

- `backend/main.py`: HTTP server, routing, CLI, business flow
- `backend/config.py`: environment loading and config parsing
- `backend/db.py`: SQLite schema and lightweight migration
- `backend/one_click_auth.py`: one-click auth provider abstraction (`mock`, `aliyun`)
- `backend/sms.py`: SMS provider abstraction (`mock`, `aliyun`)
- `backend/aliyun_rpc.py`: Aliyun RPC signer and HTTP client
- `backend/.env.example`: environment variable template
- `backend/DEPLOY.md`: Aliyun ECS deployment guide
- `backend/deploy/fuyao-backend.service.example`: systemd template
- `backend/scripts/*.sh`: bootstrap/start/install helpers

## Supported One-Click Login Modes

- `mock`: local development, accepts `mock-access-token:<phone>`
- `aliyun`: production/staging, uses `GetMobile`

Legacy `send-code/login` endpoints remain in the codebase as fallback tooling, but the main login path is now one-click login.

## Supported SMS Verify Modes

- `aliyun`: production/staging, uses `SendSmsVerifyCode` and `CheckSmsVerifyCode`
- `mock`: local development only

## Start Locally

```bash
cp backend/.env.example backend/.env
python3 -m backend.main init-db
python3 -m backend.main seed-code [REMOVED_ACTIVATION_CODE] --batch-name initial
python3 -m backend.main doctor
python3 -m backend.main serve --host 127.0.0.1 --port 8787
```

## Routes

- `GET /healthz`
- `POST /v1/auth/one-click/login`
- `POST /v1/auth/send-code`
- `POST /v1/auth/login`
- `GET /v1/auth/me`
- `POST /v1/activation/redeem`
- `GET /v1/entitlement/status`
- `POST /v1/usage/consume`
- `POST /v1/usage/rollback`

The current product rule is activation-driven:

- not logged in: local content only
- logged in but not activated: local content only
- activated: cloud capabilities unlocked

Daily quota is now legacy compatibility only. The backend keeps quota-related fields and usage endpoints for compatibility, but `FUYAO_DAILY_QUOTA_ENABLED` defaults to `false` and quota is no longer the main product rule.

## Useful Commands

```bash
python3 -m backend.main init-db
python3 -m backend.main doctor
python3 -m backend.main seed-code [REMOVED_ACTIVATION_CODE] --batch-name initial
python3 -m backend.main serve --host 0.0.0.0 --port 8787
```

## One-Click Login Flow

1. iOS SDK calls `getLoginToken`
2. Client receives `accessToken`
3. Client posts `accessToken` to `POST /v1/auth/one-click/login`
4. Backend calls Aliyun `GetMobile`
5. On success, backend creates/updates user and session

## SMS Fallback Flow

1. Client posts phone number to `POST /v1/auth/send-code`
2. Backend calls Aliyun `SendSmsVerifyCode`
3. Client posts `phone + code` to `POST /v1/auth/login`
4. Backend calls Aliyun `CheckSmsVerifyCode`
5. On success, backend creates/updates user and session with the same user model as one-click login

## Legacy Usage Compatibility

- `POST /v1/usage/consume` and `POST /v1/usage/rollback` are retained for compatibility
- when `FUYAO_DAILY_QUOTA_ENABLED=false`, activation still gates cloud access, but daily quota is not enforced
- unified auth/status responses expose `entitlement.dailyQuotaEnabled=false` so clients can stop expressing daily quota as the current product rule

## Deployment

See `backend/DEPLOY.md`.
