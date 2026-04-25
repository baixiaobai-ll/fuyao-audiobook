from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path


def _load_env_file() -> None:
    root_dir = Path(__file__).resolve().parent.parent
    env_file = Path(os.getenv("FUYAO_ENV_FILE", root_dir / "backend" / ".env")).expanduser()
    if not env_file.exists():
        return

    for raw_line in env_file.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            continue
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", "\""}:
            value = value[1:-1]
        os.environ.setdefault(key, value)


def _env_int(name: str, default: int) -> int:
    value = os.getenv(name)
    if value is None or value == "":
        return default
    return int(value)


def _env_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None or value == "":
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _env_json_dict(name: str) -> dict[str, str]:
    raw = os.getenv(name)
    if not raw:
        return {}
    value = json.loads(raw)
    if not isinstance(value, dict):
        raise ValueError(f"{name} must be a JSON object.")
    return {str(k): str(v) for k, v in value.items()}


@dataclass(frozen=True)
class AppConfig:
    root_dir: Path
    db_path: Path
    host: str
    port: int
    timezone_name: str
    session_ttl_days: int
    sms_code_ttl_seconds: int
    sms_resend_seconds: int
    daily_quota_enabled: bool
    daily_chapter_limit: int
    one_click_provider: str
    one_click_mock_phone: str
    sms_provider: str
    sms_mock_code: str | None
    aliyun_access_key_id: str | None
    aliyun_access_key_secret: str | None
    aliyun_region_id: str
    aliyun_endpoint: str
    aliyun_country_code: str
    aliyun_scheme_name: str | None
    aliyun_sms_sign_name: str | None
    aliyun_sms_template_code: str | None
    aliyun_sms_template_param_code_key: str
    aliyun_sms_template_param_minutes_key: str | None
    aliyun_sms_template_extra_params: dict[str, str]
    aliyun_sms_code_length: int
    aliyun_sms_code_type: int
    aliyun_sms_interval_seconds: int
    aliyun_sms_duplicate_policy: int
    aliyun_sms_validity_seconds: int
    aliyun_sms_auto_retry: int
    aliyun_sms_return_verify_code: bool
    aliyun_http_timeout_seconds: int


def load_config() -> AppConfig:
    _load_env_file()

    root_dir = Path(__file__).resolve().parent.parent
    default_db = root_dir / "backend" / "data" / "fuyao.sqlite3"
    db_path = Path(os.getenv("FUYAO_BACKEND_DB", default_db)).expanduser()

    sms_code_ttl_seconds = _env_int("FUYAO_SMS_CODE_TTL_SECONDS", 300)
    sms_resend_seconds = _env_int("FUYAO_SMS_RESEND_SECONDS", 60)

    return AppConfig(
        root_dir=root_dir,
        db_path=db_path,
        host=os.getenv("FUYAO_BACKEND_HOST", "127.0.0.1"),
        port=_env_int("FUYAO_BACKEND_PORT", 8787),
        timezone_name=os.getenv("FUYAO_TIMEZONE", "Asia/Shanghai"),
        session_ttl_days=_env_int("FUYAO_SESSION_TTL_DAYS", 30),
        sms_code_ttl_seconds=sms_code_ttl_seconds,
        sms_resend_seconds=sms_resend_seconds,
        daily_quota_enabled=_env_bool("FUYAO_DAILY_QUOTA_ENABLED", False),
        daily_chapter_limit=_env_int("FUYAO_DAILY_CHAPTER_LIMIT", 10),
        one_click_provider=os.getenv("FUYAO_ONE_CLICK_PROVIDER", "mock").strip().lower(),
        one_click_mock_phone=os.getenv("FUYAO_ONE_CLICK_MOCK_PHONE", "13800138000"),
        sms_provider=os.getenv("FUYAO_SMS_PROVIDER", "mock").strip().lower(),
        sms_mock_code=os.getenv("FUYAO_SMS_MOCK_CODE") or None,
        aliyun_access_key_id=os.getenv("FUYAO_ALIYUN_ACCESS_KEY_ID") or None,
        aliyun_access_key_secret=os.getenv("FUYAO_ALIYUN_ACCESS_KEY_SECRET") or None,
        aliyun_region_id=os.getenv("FUYAO_ALIYUN_REGION_ID", "cn-hangzhou"),
        aliyun_endpoint=os.getenv("FUYAO_ALIYUN_ENDPOINT", "https://dypnsapi.aliyuncs.com"),
        aliyun_country_code=os.getenv("FUYAO_ALIYUN_COUNTRY_CODE", "86"),
        aliyun_scheme_name=os.getenv("FUYAO_ALIYUN_SCHEME_NAME") or None,
        aliyun_sms_sign_name=os.getenv("FUYAO_ALIYUN_SMS_SIGN_NAME") or None,
        aliyun_sms_template_code=os.getenv("FUYAO_ALIYUN_SMS_TEMPLATE_CODE") or None,
        aliyun_sms_template_param_code_key=os.getenv("FUYAO_ALIYUN_SMS_TEMPLATE_PARAM_CODE_KEY", "code"),
        aliyun_sms_template_param_minutes_key=os.getenv("FUYAO_ALIYUN_SMS_TEMPLATE_PARAM_MINUTES_KEY") or None,
        aliyun_sms_template_extra_params=_env_json_dict("FUYAO_ALIYUN_SMS_TEMPLATE_EXTRA_PARAMS"),
        aliyun_sms_code_length=_env_int("FUYAO_ALIYUN_SMS_CODE_LENGTH", 6),
        aliyun_sms_code_type=_env_int("FUYAO_ALIYUN_SMS_CODE_TYPE", 1),
        aliyun_sms_interval_seconds=_env_int("FUYAO_ALIYUN_SMS_INTERVAL_SECONDS", sms_resend_seconds),
        aliyun_sms_duplicate_policy=_env_int("FUYAO_ALIYUN_SMS_DUPLICATE_POLICY", 1),
        aliyun_sms_validity_seconds=_env_int(
            "FUYAO_ALIYUN_SMS_VALIDITY_SECONDS",
            sms_code_ttl_seconds,
        ),
        aliyun_sms_auto_retry=_env_int("FUYAO_ALIYUN_SMS_AUTO_RETRY", 1),
        aliyun_sms_return_verify_code=_env_bool("FUYAO_ALIYUN_SMS_RETURN_VERIFY_CODE", False),
        aliyun_http_timeout_seconds=_env_int("FUYAO_ALIYUN_HTTP_TIMEOUT_SECONDS", 10),
    )
