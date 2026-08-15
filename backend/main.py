from __future__ import annotations

import argparse
import hashlib
import json
import re
import secrets
from dataclasses import replace
from datetime import datetime, timedelta, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import urlparse
from zoneinfo import ZoneInfo

from .config import AppConfig, load_config
from .db import Database
from .one_click_auth import (
    OneClickAuthExchangeError,
    OneClickAuthProvider,
    build_one_click_auth_provider,
)
from .sms import SmsProvider, SmsSendError, SmsVerifyError, build_sms_provider


PHONE_RE = re.compile(r"^1\d{10}$")
ACTIVATION_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
ACTIVATION_CODE_PAYLOAD_LENGTH = 12
ACTIVATION_CODE_CHECKSUM_LENGTH = 2
GENERATED_ACTIVATION_CODE_RE = re.compile(r"^([A-Z0-9]{1,6})-([A-Z0-9]{4})-([A-Z0-9]{4})-([A-Z0-9]{4})-([A-Z0-9]{2})$")


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def iso_now() -> str:
    return utc_now().replace(microsecond=0).isoformat()


def parse_iso(value: str | None) -> datetime | None:
    if not value:
        return None
    return datetime.fromisoformat(value)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def day_key(config: AppConfig, when: datetime | None = None) -> str:
    current = when or utc_now()
    return current.astimezone(ZoneInfo(config.timezone_name)).strftime("%Y-%m-%d")


def random_code(length: int = 6) -> str:
    upper = min(max(length, 4), 8)
    return f"{secrets.randbelow(10 ** upper):0{upper}d}"


def normalize_activation_code(value: str) -> str:
    return re.sub(r"\s+", "", value).upper()


def activation_code_checksum(payload: str, length: int = ACTIVATION_CODE_CHECKSUM_LENGTH) -> str:
    digest = hashlib.sha256(payload.encode("utf-8")).digest()
    value = int.from_bytes(digest[:8], "big")
    chars: list[str] = []
    base = len(ACTIVATION_CODE_ALPHABET)
    for _ in range(length):
        chars.append(ACTIVATION_CODE_ALPHABET[value % base])
        value //= base
    return "".join(chars)


def format_activation_code(prefix: str, payload: str, checksum: str) -> str:
    groups = [payload[i : i + 4] for i in range(0, len(payload), 4)]
    return "-".join([prefix, *groups, checksum])


def generate_activation_code(prefix: str = "FY") -> str:
    clean_prefix = re.sub(r"[^A-Z0-9]", "", prefix.upper())[:6] or "FY"
    payload = "".join(secrets.choice(ACTIVATION_CODE_ALPHABET) for _ in range(ACTIVATION_CODE_PAYLOAD_LENGTH))
    checksum = activation_code_checksum(f"{clean_prefix}-{payload}")
    return format_activation_code(clean_prefix, payload, checksum)


def generated_activation_code_has_valid_checksum(code: str) -> bool | None:
    match = GENERATED_ACTIVATION_CODE_RE.fullmatch(code)
    if not match:
        return None
    prefix = match.group(1)
    payload = "".join(match.group(i) for i in range(2, 5))
    checksum = match.group(5)
    return activation_code_checksum(f"{prefix}-{payload}") == checksum


def read_json(handler: BaseHTTPRequestHandler) -> dict[str, Any]:
    length = int(handler.headers.get("Content-Length", "0"))
    raw = handler.rfile.read(length) if length > 0 else b"{}"
    try:
        data = json.loads(raw.decode("utf-8") or "{}")
    except json.JSONDecodeError as exc:
        raise ApiError(400, "invalid_json", "Request body must be valid JSON.") from exc
    if not isinstance(data, dict):
        raise ApiError(400, "invalid_json", "Request body must be a JSON object.")
    return data


def json_response(handler: BaseHTTPRequestHandler, status: int, payload: dict[str, Any]) -> None:
    body = json.dumps(payload, ensure_ascii=True).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def session_token() -> str:
    return secrets.token_urlsafe(32)


def request_id() -> str:
    return secrets.token_hex(16)


def validate_phone(phone: str) -> str:
    normalized = phone.strip()
    if not PHONE_RE.fullmatch(normalized):
        raise ApiError(400, "invalid_phone", "Phone must be an 11-digit mainland China mobile number.")
    return normalized


def summarize_permissions(logged_in: bool, activated: bool) -> dict[str, Any]:
    return {
        "canUseLocalBooks": True,
        "canUseDiscover": logged_in and activated,
        "canUseCloudBooks": logged_in and activated,
        "canUseCloudCapabilities": logged_in and activated,
        "canRedeemActivationCode": logged_in and not activated,
    }


def ensure_entitlement(conn, user_id: int, config: AppConfig):
    row = conn.execute(
        """
        SELECT id, user_id, is_activated, activated_at, activation_code_id,
               daily_chapter_limit, created_at, updated_at
        FROM user_entitlements
        WHERE user_id = ?
        """,
        (user_id,),
    ).fetchone()
    if row:
        return row

    now = iso_now()
    conn.execute(
        """
        INSERT INTO user_entitlements (
            user_id, is_activated, daily_chapter_limit, created_at, updated_at
        ) VALUES (?, 0, ?, ?, ?)
        """,
        (user_id, config.daily_chapter_limit, now, now),
    )
    return conn.execute(
        """
        SELECT id, user_id, is_activated, activated_at, activation_code_id,
               daily_chapter_limit, created_at, updated_at
        FROM user_entitlements
        WHERE user_id = ?
        """,
        (user_id,),
    ).fetchone()


def used_today(conn, user_id: int, usage_day: str) -> int:
    row = conn.execute(
        """
        SELECT COUNT(1) AS total
        FROM daily_usage
        WHERE user_id = ? AND usage_day = ? AND status = 'consumed'
        """,
        (user_id, usage_day),
    ).fetchone()
    return int(row["total"] if row else 0)


def status_payload(conn, config: AppConfig, user_row=None) -> dict[str, Any]:
    if not user_row:
        return {
            "loggedIn": False,
            "user": None,
            "entitlement": {
                "accessMode": "activation",
                "isActivated": False,
                "dailyQuotaEnabled": config.daily_quota_enabled,
                "dailyChapterLimit": config.daily_chapter_limit,
                "usageDay": day_key(config),
                "usedToday": 0,
                "remainingToday": 0,
            },
            "permissions": summarize_permissions(False, False),
        }

    entitlement = ensure_entitlement(conn, int(user_row["id"]), config)
    usage_day = day_key(config)
    used = used_today(conn, int(user_row["id"]), usage_day)
    limit = int(entitlement["daily_chapter_limit"])
    activated = bool(entitlement["is_activated"])
    remaining = max(limit - used, 0) if activated else 0
    return {
        "loggedIn": True,
        "user": {
            "id": int(user_row["id"]),
            "phone": user_row["phone"],
            "nickname": user_row["nickname"],
            "createdAt": user_row["created_at"],
            "lastLoginAt": user_row["last_login_at"],
        },
        "entitlement": {
            "accessMode": "activation",
            "isActivated": activated,
            "activatedAt": entitlement["activated_at"],
            "activationCodeId": entitlement["activation_code_id"],
            "dailyQuotaEnabled": config.daily_quota_enabled,
            "dailyChapterLimit": limit,
            "usageDay": usage_day,
            "usedToday": used if activated else 0,
            "remainingToday": remaining,
        },
        "permissions": summarize_permissions(True, activated),
    }


def extract_bearer_token(handler: BaseHTTPRequestHandler, required: bool) -> str | None:
    header = handler.headers.get("Authorization", "").strip()
    if not header:
        if required:
            raise ApiError(401, "unauthorized", "Missing Authorization header.")
        return None
    if not header.startswith("Bearer "):
        raise ApiError(401, "unauthorized", "Authorization header must use Bearer token.")
    token = header[7:].strip()
    if not token and required:
        raise ApiError(401, "unauthorized", "Missing bearer token.")
    return token or None


class FuyaoBackendApp:
    def __init__(
        self,
        config: AppConfig,
        db: Database,
        sms_provider: SmsProvider,
        one_click_provider: OneClickAuthProvider,
    ):
        self.config = config
        self.db = db
        self.sms_provider = sms_provider
        self.one_click_provider = one_click_provider

    def _effective_sms_code_ttl_seconds(self) -> int:
        if self.sms_provider.name == "aliyun":
            return self.config.aliyun_sms_validity_seconds
        return self.config.sms_code_ttl_seconds

    def _effective_sms_retry_after_seconds(self) -> int:
        if self.sms_provider.name == "aliyun":
            return max(self.config.sms_resend_seconds, self.config.aliyun_sms_interval_seconds)
        return self.config.sms_resend_seconds

    def authenticate(self, handler: BaseHTTPRequestHandler, required: bool = True):
        token = extract_bearer_token(handler, required=required)
        if token is None:
            return None

        with self.db.connect() as conn:
            row = conn.execute(
                """
                SELECT s.id AS session_id, s.user_id, s.expires_at, u.id, u.phone, u.nickname,
                       u.created_at, u.last_login_at
                FROM sessions s
                JOIN users u ON u.id = s.user_id
                WHERE s.token_hash = ?
                """,
                (hash_token(token),),
            ).fetchone()
            if not row:
                raise ApiError(401, "unauthorized", "Session token is invalid.")

            expires_at = parse_iso(row["expires_at"])
            if expires_at is None or expires_at <= utc_now():
                raise ApiError(401, "session_expired", "Session token has expired.")

            conn.execute(
                "UPDATE sessions SET last_seen_at = ? WHERE id = ?",
                (iso_now(), row["session_id"]),
            )

            return {
                "sessionId": int(row["session_id"]),
                "user": {
                    "id": int(row["id"]),
                    "phone": row["phone"],
                    "nickname": row["nickname"],
                    "created_at": row["created_at"],
                    "last_login_at": row["last_login_at"],
                },
                "expiresAt": row["expires_at"],
            }

    def _login_or_register_user(self, conn, phone: str) -> dict[str, Any]:
        now = iso_now()
        user = conn.execute(
            "SELECT id, phone, nickname, created_at, last_login_at FROM users WHERE phone = ?",
            (phone,),
        ).fetchone()
        if user:
            conn.execute(
                "UPDATE users SET last_login_at = ? WHERE id = ?",
                (now, user["id"]),
            )
            user_id = int(user["id"])
        else:
            nickname = f"user_{phone[-4:]}"
            conn.execute(
                """
                INSERT INTO users (phone, nickname, created_at, last_login_at)
                VALUES (?, ?, ?, ?)
                """,
                (phone, nickname, now, now),
            )
            user_id = int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])

        ensure_entitlement(conn, user_id, self.config)
        raw_token = session_token()
        expires_at = (
            utc_now() + timedelta(days=self.config.session_ttl_days)
        ).replace(microsecond=0).isoformat()
        conn.execute(
            """
            INSERT INTO sessions (user_id, token_hash, expires_at, created_at, last_seen_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (user_id, hash_token(raw_token), expires_at, now, now),
        )
        user_row = conn.execute(
            "SELECT id, phone, nickname, created_at, last_login_at FROM users WHERE id = ?",
            (user_id,),
        ).fetchone()
        response = status_payload(conn, self.config, user_row)
        response["token"] = raw_token
        response["session"] = {"expiresAt": expires_at}
        return response

    def handle_one_click_login(self, handler: BaseHTTPRequestHandler) -> None:
        payload = read_json(handler)
        access_token = str(payload.get("accessToken", "")).strip()
        issued_request_id = str(payload.get("requestId", "")).strip() or request_id()
        if not access_token:
            raise ApiError(400, "invalid_access_token", "accessToken is required.")

        access_token_hash = hash_token(access_token)
        with self.db.transaction() as conn:
            existing_token_use = conn.execute(
                """
                SELECT request_id, phone_number
                FROM one_click_auth_requests
                WHERE access_token_hash = ? AND status = 'verified'
                """,
                (access_token_hash,),
            ).fetchone()
            if existing_token_use:
                raise ApiError(409, "access_token_used", "accessToken has already been used.")

            try:
                exchange_result = self.one_click_provider.exchange_access_token(access_token, issued_request_id)
            except OneClickAuthExchangeError as exc:
                raise ApiError(exc.http_status, "one_click_login_failed", str(exc)) from exc

            now = iso_now()
            if not exchange_result.passed or not exchange_result.phone_number:
                conn.execute(
                    """
                    INSERT INTO one_click_auth_requests (
                        request_id, provider, access_token_hash, phone_number, status,
                        provider_request_id, provider_result, created_at, verified_at, raw_payload
                    ) VALUES (?, ?, ?, ?, 'failed', ?, ?, ?, ?, ?)
                    """,
                    (
                        issued_request_id,
                        exchange_result.provider,
                        access_token_hash,
                        exchange_result.phone_number,
                        exchange_result.provider_request_id,
                        exchange_result.provider_result,
                        now,
                        now,
                        exchange_result.raw_response,
                    ),
                )
                raise ApiError(401, "one_click_login_failed", "One-click login did not return a phone number.")

            conn.execute(
                """
                INSERT INTO one_click_auth_requests (
                    request_id, provider, access_token_hash, phone_number, status,
                    provider_request_id, provider_result, created_at, verified_at, raw_payload
                ) VALUES (?, ?, ?, ?, 'verified', ?, ?, ?, ?, ?)
                """,
                (
                    issued_request_id,
                    exchange_result.provider,
                    access_token_hash,
                    exchange_result.phone_number,
                    exchange_result.provider_request_id,
                    exchange_result.provider_result,
                    now,
                    now,
                    exchange_result.raw_response,
                ),
            )

            response = self._login_or_register_user(conn, validate_phone(exchange_result.phone_number))
        json_response(handler, 200, response)

    def handle_send_code(self, handler: BaseHTTPRequestHandler) -> None:
        payload = read_json(handler)
        phone = validate_phone(str(payload.get("phone", "")))
        retry_after_seconds = self._effective_sms_retry_after_seconds()
        expires_in_seconds = self._effective_sms_code_ttl_seconds()

        with self.db.transaction() as conn:
            latest = conn.execute(
                """
                SELECT created_at
                FROM sms_codes
                WHERE phone = ? AND purpose = 'login'
                ORDER BY id DESC
                LIMIT 1
                """,
                (phone,),
            ).fetchone()
            if latest:
                last_sent_at = parse_iso(latest["created_at"])
                if last_sent_at is not None:
                    wait_seconds = retry_after_seconds - int((utc_now() - last_sent_at).total_seconds())
                    if wait_seconds > 0:
                        raise ApiError(
                            429,
                            "too_many_requests",
                            f"Please wait {wait_seconds} seconds before requesting another code.",
                        )

            generated_code = ""
            if self.sms_provider.stores_local_code:
                generated_code = self.config.sms_mock_code or random_code(
                    self.config.aliyun_sms_code_length
                )
            created_at = iso_now()
            expires_at = (
                utc_now() + timedelta(seconds=expires_in_seconds)
            ).replace(microsecond=0).isoformat()
            sms_request_id = request_id()

            try:
                result = self.sms_provider.send_verification_code(
                    phone=phone,
                    code=generated_code,
                    request_id=sms_request_id,
                    ttl_seconds=expires_in_seconds,
                )
            except SmsSendError as exc:
                raise ApiError(
                    exc.http_status,
                    "sms_send_failed",
                    str(exc),
                ) from exc

            conn.execute(
                """
                INSERT INTO sms_codes (
                    phone, purpose, code, provider, status, expires_at, created_at, request_id,
                    provider_request_id, provider_biz_id, provider_payload
                ) VALUES (?, 'login', ?, ?, 'sent', ?, ?, ?, ?, ?, ?)
                """,
                (
                    phone,
                    generated_code if self.sms_provider.stores_local_code else "",
                    result.provider,
                    expires_at,
                    created_at,
                    sms_request_id,
                    result.provider_request_id,
                    result.provider_biz_id,
                    result.raw_response,
                ),
            )

        response = {
            "ok": True,
            "phone": phone,
            "provider": self.sms_provider.name,
            "requestId": sms_request_id,
            "expiresIn": expires_in_seconds,
            "retryAfter": retry_after_seconds,
        }
        if self.sms_provider.name == "mock" and result.issued_code:
            response["debugCode"] = result.issued_code
        json_response(handler, 200, response)

    def handle_login(self, handler: BaseHTTPRequestHandler) -> None:
        payload = read_json(handler)
        phone = validate_phone(str(payload.get("phone", "")))
        code = str(payload.get("code", "")).strip()
        if not re.fullmatch(r"\d{4,8}", code):
            raise ApiError(400, "invalid_code", "Verification code must be 4 to 8 digits.")

        now = iso_now()

        with self.db.transaction() as conn:
            sms_row = conn.execute(
                """
                SELECT id, code, provider, expires_at, status, request_id,
                       provider_request_id, provider_biz_id, provider_verify_result, provider_payload
                FROM sms_codes
                WHERE phone = ? AND purpose = 'login'
                ORDER BY id DESC
                LIMIT 1
                """,
                (phone,),
            ).fetchone()
            if not sms_row:
                raise ApiError(401, "code_not_found", "Verification code was not sent.")
            if sms_row["status"] != "sent":
                raise ApiError(401, "code_already_used", "Verification code has already been used.")
            expires = parse_iso(sms_row["expires_at"])
            if expires is None or expires <= utc_now():
                raise ApiError(401, "code_expired", "Verification code has expired.")

            try:
                verify_result = self.sms_provider.verify_code(phone, code, sms_row)
            except SmsVerifyError as exc:
                raise ApiError(exc.http_status, "sms_verify_failed", str(exc)) from exc

            conn.execute(
                """
                UPDATE sms_codes
                SET provider_verify_result = ?, provider_payload = COALESCE(?, provider_payload)
                WHERE id = ?
                """,
                (verify_result.provider_result, verify_result.raw_response, sms_row["id"]),
            )

            if not verify_result.passed:
                raise ApiError(401, "invalid_code", "Verification code is incorrect.")

            conn.execute(
                "UPDATE sms_codes SET status = 'used', used_at = ? WHERE id = ?",
                (now, sms_row["id"]),
            )

            user = conn.execute(
                "SELECT id, phone, nickname, created_at, last_login_at FROM users WHERE phone = ?",
                (phone,),
            ).fetchone()
            response = self._login_or_register_user(conn, phone)
        json_response(handler, 200, response)

    def handle_auth_me(self, handler: BaseHTTPRequestHandler) -> None:
        session = self.authenticate(handler, required=True)
        with self.db.connect() as conn:
            user_row = conn.execute(
                "SELECT id, phone, nickname, created_at, last_login_at FROM users WHERE id = ?",
                (session["user"]["id"],),
            ).fetchone()
            response = status_payload(conn, self.config, user_row)
            response["session"] = {"expiresAt": session["expiresAt"]}
        json_response(handler, 200, response)

    def handle_profile_update(self, handler: BaseHTTPRequestHandler) -> None:
        session = self.authenticate(handler, required=True)
        payload = read_json(handler)
        raw_nickname = str(payload.get("nickname", "")).strip()
        nickname = re.sub(r"\s+", " ", raw_nickname)
        if not nickname:
            raise ApiError(400, "invalid_nickname", "Nickname cannot be empty.")
        if len(nickname) > 20:
            raise ApiError(400, "invalid_nickname", "Nickname must be at most 20 characters.")

        with self.db.transaction() as conn:
            conn.execute(
                "UPDATE users SET nickname = ? WHERE id = ?",
                (nickname, session["user"]["id"]),
            )
            user_row = conn.execute(
                "SELECT id, phone, nickname, created_at, last_login_at FROM users WHERE id = ?",
                (session["user"]["id"],),
            ).fetchone()
            response = status_payload(conn, self.config, user_row)
            response["session"] = {"expiresAt": session["expiresAt"]}
        json_response(handler, 200, response)

    def handle_activation_redeem(self, handler: BaseHTTPRequestHandler) -> None:
        session = self.authenticate(handler, required=True)
        payload = read_json(handler)
        code = normalize_activation_code(str(payload.get("code", "")))
        if not code:
            raise ApiError(400, "invalid_activation_code", "Activation code is required.")
        checksum_valid = generated_activation_code_has_valid_checksum(code)
        if checksum_valid is False:
            raise ApiError(400, "invalid_activation_code", "Activation code checksum is invalid.")

        now = iso_now()
        with self.db.transaction() as conn:
            activation = conn.execute(
                """
                SELECT id, code, status, expires_at, redeemed_by_user_id
                FROM activation_codes
                WHERE code = ?
                """,
                (code,),
            ).fetchone()
            if not activation:
                raise ApiError(404, "activation_code_not_found", "Activation code does not exist.")
            if activation["status"] == "redeemed":
                if int(activation["redeemed_by_user_id"] or 0) == session["user"]["id"]:
                    user_row = conn.execute(
                        "SELECT id, phone, nickname, created_at, last_login_at FROM users WHERE id = ?",
                        (session["user"]["id"],),
                    ).fetchone()
                    response = status_payload(conn, self.config, user_row)
                    response["redeemStatus"] = "already_redeemed"
                    json_response(handler, 200, response)
                    return
                raise ApiError(409, "activation_code_used", "Activation code has already been redeemed.")
            expires = parse_iso(activation["expires_at"])
            if expires is not None and expires <= utc_now():
                raise ApiError(409, "activation_code_expired", "Activation code has expired.")

            conn.execute(
                """
                UPDATE activation_codes
                SET status = 'redeemed', redeemed_by_user_id = ?, redeemed_at = ?
                WHERE id = ?
                """,
                (session["user"]["id"], now, activation["id"]),
            )

            entitlement = ensure_entitlement(conn, session["user"]["id"], self.config)
            conn.execute(
                """
                UPDATE user_entitlements
                SET is_activated = 1,
                    activated_at = COALESCE(activated_at, ?),
                    activation_code_id = ?,
                    updated_at = ?
                WHERE id = ?
                """,
                (now, activation["id"], now, entitlement["id"]),
            )
            user_row = conn.execute(
                "SELECT id, phone, nickname, created_at, last_login_at FROM users WHERE id = ?",
                (session["user"]["id"],),
            ).fetchone()
            response = status_payload(conn, self.config, user_row)
            response["redeemStatus"] = "redeemed"
        json_response(handler, 200, response)

    def handle_entitlement_status(self, handler: BaseHTTPRequestHandler) -> None:
        session = self.authenticate(handler, required=False)
        with self.db.connect() as conn:
            if session is None:
                response = status_payload(conn, self.config, None)
            else:
                user_row = conn.execute(
                    "SELECT id, phone, nickname, created_at, last_login_at FROM users WHERE id = ?",
                    (session["user"]["id"],),
                ).fetchone()
                response = status_payload(conn, self.config, user_row)
        json_response(handler, 200, response)

    def handle_usage_consume(self, handler: BaseHTTPRequestHandler) -> None:
        session = self.authenticate(handler, required=True)
        payload = read_json(handler)
        consume_request_id = str(payload.get("requestId", "")).strip()
        book_id = str(payload.get("bookId", "")).strip()
        chapter_index = payload.get("chapterIndex")

        if not consume_request_id:
            raise ApiError(400, "invalid_request_id", "requestId is required.")
        if not book_id:
            raise ApiError(400, "invalid_book_id", "bookId is required.")
        if not isinstance(chapter_index, int) or chapter_index < 0:
            raise ApiError(400, "invalid_chapter_index", "chapterIndex must be a non-negative integer.")

        usage_day = day_key(self.config)
        with self.db.transaction() as conn:
            user_id = session["user"]["id"]
            entitlement = ensure_entitlement(conn, user_id, self.config)
            if not bool(entitlement["is_activated"]):
                raise ApiError(403, "not_activated", "Activation is required before using cloud capabilities.")

            existing = conn.execute(
                """
                SELECT status
                FROM daily_usage
                WHERE user_id = ? AND request_id = ?
                """,
                (user_id, consume_request_id),
            ).fetchone()
            if existing:
                current_used = used_today(conn, user_id, usage_day)
                response = {
                    "requestId": consume_request_id,
                    "status": "already_consumed" if existing["status"] == "consumed" else "already_rolled_back",
                    "quotaApplied": self.config.daily_quota_enabled,
                    "usageDay": usage_day,
                    "usedToday": current_used,
                    "remainingToday": max(int(entitlement["daily_chapter_limit"]) - current_used, 0),
                }
                json_response(handler, 200, response)
                return

            current_used = used_today(conn, user_id, usage_day)
            limit = int(entitlement["daily_chapter_limit"])
            if self.config.daily_quota_enabled and current_used >= limit:
                raise ApiError(403, "quota_exceeded", "Daily chapter quota has been exhausted.")

            conn.execute(
                """
                INSERT INTO daily_usage (
                    user_id, usage_day, request_id, book_id, chapter_index, status, consumed_at
                ) VALUES (?, ?, ?, ?, ?, 'consumed', ?)
                """,
                (user_id, usage_day, consume_request_id, book_id, chapter_index, iso_now()),
            )
            updated_used = current_used + 1
            response = {
                "requestId": consume_request_id,
                "status": "consumed",
                "quotaApplied": self.config.daily_quota_enabled,
                "usageDay": usage_day,
                "usedToday": updated_used,
                "remainingToday": max(limit - updated_used, 0),
            }
        json_response(handler, 200, response)

    def handle_usage_rollback(self, handler: BaseHTTPRequestHandler) -> None:
        session = self.authenticate(handler, required=True)
        payload = read_json(handler)
        rollback_request_id = str(payload.get("requestId", "")).strip()
        rollback_reason = str(payload.get("reason", "")).strip() or "generation_failed"
        if not rollback_request_id:
            raise ApiError(400, "invalid_request_id", "requestId is required.")

        usage_day = day_key(self.config)
        with self.db.transaction() as conn:
            user_id = session["user"]["id"]
            row = conn.execute(
                """
                SELECT id, status
                FROM daily_usage
                WHERE user_id = ? AND request_id = ?
                """,
                (user_id, rollback_request_id),
            ).fetchone()
            if not row:
                raise ApiError(404, "usage_not_found", "No usage record matches the requestId.")

            if row["status"] == "rolled_back":
                current_used = used_today(conn, user_id, usage_day)
                limit = int(ensure_entitlement(conn, user_id, self.config)["daily_chapter_limit"])
                response = {
                    "requestId": rollback_request_id,
                    "status": "already_rolled_back",
                    "quotaApplied": self.config.daily_quota_enabled,
                    "usageDay": usage_day,
                    "usedToday": current_used,
                    "remainingToday": max(limit - current_used, 0),
                }
                json_response(handler, 200, response)
                return

            conn.execute(
                """
                UPDATE daily_usage
                SET status = 'rolled_back', rolled_back_at = ?, rollback_reason = ?
                WHERE id = ?
                """,
                (iso_now(), rollback_reason, row["id"]),
            )
            current_used = used_today(conn, user_id, usage_day)
            limit = int(ensure_entitlement(conn, user_id, self.config)["daily_chapter_limit"])
            response = {
                "requestId": rollback_request_id,
                "status": "rolled_back",
                "quotaApplied": self.config.daily_quota_enabled,
                "usageDay": usage_day,
                "usedToday": current_used,
                "remainingToday": max(limit - current_used, 0),
            }
        json_response(handler, 200, response)

    def handle_health(self, handler: BaseHTTPRequestHandler) -> None:
        json_response(
            handler,
            200,
            {
                "ok": True,
                "service": "fuyao-backend",
                "smsProvider": self.sms_provider.name,
                "oneClickProvider": self.one_click_provider.name,
                "time": iso_now(),
            },
        )


class ApiHandler(BaseHTTPRequestHandler):
    app: FuyaoBackendApp

    def do_GET(self) -> None:
        self._dispatch()

    def do_POST(self) -> None:
        self._dispatch()

    def do_PATCH(self) -> None:
        self._dispatch()

    def log_message(self, format: str, *args) -> None:
        return

    def _dispatch(self) -> None:
        path = urlparse(self.path).path
        try:
            if self.command == "GET" and path == "/healthz":
                self.app.handle_health(self)
                return
            if self.command == "POST" and path == "/v1/auth/one-click/login":
                self.app.handle_one_click_login(self)
                return
            if self.command == "POST" and path == "/v1/auth/send-code":
                self.app.handle_send_code(self)
                return
            if self.command == "POST" and path == "/v1/auth/login":
                self.app.handle_login(self)
                return
            if self.command == "GET" and path == "/v1/auth/me":
                self.app.handle_auth_me(self)
                return
            if self.command == "PATCH" and path == "/v1/profile":
                self.app.handle_profile_update(self)
                return
            if self.command == "POST" and path == "/v1/activation/redeem":
                self.app.handle_activation_redeem(self)
                return
            if self.command == "GET" and path == "/v1/entitlement/status":
                self.app.handle_entitlement_status(self)
                return
            if self.command == "POST" and path == "/v1/usage/consume":
                self.app.handle_usage_consume(self)
                return
            if self.command == "POST" and path == "/v1/usage/rollback":
                self.app.handle_usage_rollback(self)
                return
            raise ApiError(404, "not_found", f"Unsupported route: {self.command} {path}")
        except ApiError as exc:
            json_response(
                self,
                exc.status,
                {"error": {"code": exc.code, "message": exc.message}},
            )
        except Exception as exc:
            json_response(
                self,
                HTTPStatus.INTERNAL_SERVER_ERROR,
                {"error": {"code": "internal_error", "message": str(exc)}},
            )


def build_server(config: AppConfig) -> ThreadingHTTPServer:
    db = Database(config.db_path)
    db.initialize()
    app = FuyaoBackendApp(
        config=config,
        db=db,
        sms_provider=build_sms_provider(config),
        one_click_provider=build_one_click_auth_provider(config),
    )
    ApiHandler.app = app
    return ThreadingHTTPServer((config.host, config.port), ApiHandler)


def insert_activation_code(config: AppConfig, code: str, batch_name: str, expires_at: str | None) -> bool:
    normalized = normalize_activation_code(code)
    db = Database(config.db_path)
    db.initialize()
    with db.transaction() as conn:
        existing = conn.execute(
            "SELECT id FROM activation_codes WHERE code = ?",
            (normalized,),
        ).fetchone()
        if existing:
            return False
        conn.execute(
            """
            INSERT INTO activation_codes (code, batch_name, status, expires_at, created_at)
            VALUES (?, ?, 'new', ?, ?)
            """,
            (normalized, batch_name, expires_at, iso_now()),
        )
    return True


def seed_activation_code(config: AppConfig, code: str, batch_name: str, expires_at: str | None) -> None:
    normalized = normalize_activation_code(code)
    if insert_activation_code(config, normalized, batch_name, expires_at):
        print(f"seeded activation code: {normalized}")
    else:
        print(f"activation code already exists: {normalized}")


def generate_activation_codes(
    config: AppConfig,
    count: int,
    batch_name: str,
    expires_at: str | None,
    prefix: str,
) -> None:
    if count < 1 or count > 1000:
        raise SystemExit("--count must be between 1 and 1000")

    created: list[str] = []
    attempts = 0
    max_attempts = count * 5
    while len(created) < count and attempts < max_attempts:
        attempts += 1
        code = generate_activation_code(prefix=prefix)
        if insert_activation_code(config, code, batch_name, expires_at):
            created.append(code)

    if len(created) != count:
        raise SystemExit(f"only generated {len(created)} activation codes after {attempts} attempts")

    print(f"generated {len(created)} activation codes:")
    for code in created:
        print(code)


def doctor(config: AppConfig) -> None:
    Database(config.db_path).initialize()
    provider = build_sms_provider(config)
    one_click_provider = build_one_click_auth_provider(config)
    masked_access_key = None
    if config.aliyun_access_key_id:
        masked_access_key = f"{config.aliyun_access_key_id[:4]}...{config.aliyun_access_key_id[-4:]}"
    summary = {
        "ok": True,
        "environment": config.environment,
        "dbPath": str(config.db_path),
        "host": config.host,
        "port": config.port,
        "smsProvider": provider.name,
        "oneClickProvider": one_click_provider.name,
        "aliyunEndpoint": config.aliyun_endpoint if provider.name == "aliyun" or one_click_provider.name == "aliyun" else None,
        "aliyunAccessKeyId": masked_access_key,
    }
    print(json.dumps(summary, ensure_ascii=True))


def main() -> None:
    parser = argparse.ArgumentParser(description="Fuyao minimal backend")
    subparsers = parser.add_subparsers(dest="command")

    serve_parser = subparsers.add_parser("serve", help="Run HTTP server")
    serve_parser.add_argument("--host")
    serve_parser.add_argument("--port", type=int)

    subparsers.add_parser("init-db", help="Initialize SQLite schema")
    subparsers.add_parser("doctor", help="Validate config and database")

    seed_parser = subparsers.add_parser("seed-code", help="Insert one activation code")
    seed_parser.add_argument("code")
    seed_parser.add_argument("--batch-name", default="manual")
    seed_parser.add_argument("--expires-at")

    generate_parser = subparsers.add_parser("generate-codes", help="Generate activation codes")
    generate_parser.add_argument("--count", type=int, default=1)
    generate_parser.add_argument("--batch-name", default="generated")
    generate_parser.add_argument("--expires-at")
    generate_parser.add_argument("--prefix", default="FY")

    args = parser.parse_args()
    config = load_config()

    if args.command == "init-db":
        Database(config.db_path).initialize()
        print(f"database initialized at {config.db_path}")
        return

    if args.command == "doctor":
        doctor(config)
        return

    if args.command == "seed-code":
        seed_activation_code(config, args.code, args.batch_name, args.expires_at)
        return

    if args.command == "generate-codes":
        generate_activation_codes(config, args.count, args.batch_name, args.expires_at, args.prefix)
        return

    if args.command in (None, "serve"):
        config = replace(
            config,
            host=args.host or config.host,
            port=args.port or config.port,
        )
        server = build_server(config)
        print(f"Fuyao backend listening on http://{config.host}:{config.port}")
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            server.server_close()
        return

    parser.error(f"unknown command: {args.command}")


if __name__ == "__main__":
    main()
