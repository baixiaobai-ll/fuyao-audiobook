from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator


SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    phone TEXT NOT NULL UNIQUE,
    nickname TEXT NOT NULL,
    created_at TEXT NOT NULL,
    last_login_at TEXT
);

CREATE TABLE IF NOT EXISTS sms_codes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    phone TEXT NOT NULL,
    purpose TEXT NOT NULL,
    code TEXT NOT NULL,
    provider TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'sent',
    expires_at TEXT NOT NULL,
    used_at TEXT,
    created_at TEXT NOT NULL,
    request_id TEXT NOT NULL UNIQUE,
    provider_request_id TEXT,
    provider_biz_id TEXT,
    provider_verify_result TEXT,
    provider_payload TEXT
);

CREATE INDEX IF NOT EXISTS idx_sms_codes_phone_created
ON sms_codes(phone, purpose, created_at DESC);

CREATE TABLE IF NOT EXISTS sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL,
    last_seen_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_sessions_user
ON sessions(user_id, expires_at DESC);

CREATE TABLE IF NOT EXISTS activation_codes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT NOT NULL UNIQUE,
    batch_name TEXT,
    status TEXT NOT NULL DEFAULT 'new',
    expires_at TEXT,
    redeemed_by_user_id INTEGER REFERENCES users(id),
    redeemed_at TEXT,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS user_entitlements (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    is_activated INTEGER NOT NULL DEFAULT 0,
    activated_at TEXT,
    activation_code_id INTEGER REFERENCES activation_codes(id),
    daily_chapter_limit INTEGER NOT NULL DEFAULT 10,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS daily_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    usage_day TEXT NOT NULL,
    request_id TEXT NOT NULL,
    book_id TEXT NOT NULL,
    chapter_index INTEGER NOT NULL,
    status TEXT NOT NULL DEFAULT 'consumed',
    consumed_at TEXT NOT NULL,
    rolled_back_at TEXT,
    rollback_reason TEXT,
    UNIQUE(user_id, request_id)
);

CREATE INDEX IF NOT EXISTS idx_daily_usage_user_day
ON daily_usage(user_id, usage_day, status);

CREATE TABLE IF NOT EXISTS one_click_auth_requests (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    request_id TEXT NOT NULL UNIQUE,
    provider TEXT NOT NULL,
    access_token_hash TEXT NOT NULL UNIQUE,
    phone_number TEXT,
    status TEXT NOT NULL DEFAULT 'verified',
    provider_request_id TEXT,
    provider_result TEXT,
    created_at TEXT NOT NULL,
    verified_at TEXT,
    raw_payload TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_one_click_auth_access_token_hash
ON one_click_auth_requests(access_token_hash);
"""


SMS_CODES_COLUMNS = {
    "provider_request_id": "TEXT",
    "provider_biz_id": "TEXT",
    "provider_verify_result": "TEXT",
    "provider_payload": "TEXT",
}

ONE_CLICK_AUTH_REQUESTS_COLUMNS = {
    "provider_request_id": "TEXT",
    "provider_result": "TEXT",
    "raw_payload": "TEXT",
    "phone_number": "TEXT",
    "verified_at": "TEXT",
}


class Database:
    def __init__(self, db_path: Path):
        self.db_path = db_path

    def initialize(self) -> None:
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        with self.connect() as conn:
            conn.execute("PRAGMA journal_mode = WAL")
            conn.executescript(SCHEMA)
            self._migrate(conn)

    def connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=30)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        return conn

    @contextmanager
    def transaction(self) -> Iterator[sqlite3.Connection]:
        conn = self.connect()
        try:
            conn.execute("BEGIN IMMEDIATE")
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

    def _migrate(self, conn: sqlite3.Connection) -> None:
        self._ensure_columns(conn, "sms_codes", SMS_CODES_COLUMNS)
        self._ensure_columns(conn, "one_click_auth_requests", ONE_CLICK_AUTH_REQUESTS_COLUMNS)

    def _ensure_columns(
        self,
        conn: sqlite3.Connection,
        table_name: str,
        columns: dict[str, str],
    ) -> None:
        existing = {
            row["name"]
            for row in conn.execute(f"PRAGMA table_info({table_name})").fetchall()
        }
        for column_name, column_type in columns.items():
            if column_name in existing:
                continue
            try:
                conn.execute(
                    f"ALTER TABLE {table_name} ADD COLUMN {column_name} {column_type}"
                )
                existing.add(column_name)
            except sqlite3.OperationalError as exc:
                if "duplicate column name" not in str(exc).lower():
                    raise
                existing.add(column_name)
