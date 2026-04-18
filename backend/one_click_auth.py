from __future__ import annotations

import json
from dataclasses import dataclass

from .aliyun_rpc import AliyunRpcClient, AliyunRpcError
from .config import AppConfig


class OneClickAuthExchangeError(RuntimeError):
    def __init__(self, message: str, http_status: int = 502, provider_code: str | None = None):
        super().__init__(message)
        self.http_status = http_status
        self.provider_code = provider_code


@dataclass
class OneClickAuthResult:
    provider: str
    passed: bool
    phone_number: str | None = None
    provider_request_id: str | None = None
    provider_result: str | None = None
    raw_response: str | None = None


class OneClickAuthProvider:
    name = "base"

    def exchange_access_token(self, access_token: str, request_id: str) -> OneClickAuthResult:
        raise NotImplementedError


class MockOneClickAuthProvider(OneClickAuthProvider):
    name = "mock"

    def __init__(self, config: AppConfig):
        self.config = config

    def exchange_access_token(self, access_token: str, request_id: str) -> OneClickAuthResult:
        prefix = "mock-access-token:"
        if access_token.startswith(prefix):
            phone_number = access_token[len(prefix):].strip()
        else:
            phone_number = self.config.one_click_mock_phone if access_token == "mock-access-token" else ""

        if not phone_number:
            return OneClickAuthResult(
                provider=self.name,
                passed=False,
                provider_request_id=request_id,
                provider_result="INVALID_TOKEN",
                raw_response=json.dumps({"mode": "mock", "accessToken": access_token}, ensure_ascii=True),
            )

        return OneClickAuthResult(
            provider=self.name,
            passed=True,
            phone_number=phone_number,
            provider_request_id=request_id,
            provider_result="OK",
            raw_response=json.dumps({"mode": "mock", "mobile": phone_number}, ensure_ascii=True),
        )


class AliyunOneClickAuthProvider(OneClickAuthProvider):
    name = "aliyun"

    def __init__(self, config: AppConfig):
        self.config = config
        self.client = AliyunRpcClient(
            endpoint=config.aliyun_endpoint,
            access_key_id=config.aliyun_access_key_id or "",
            access_key_secret=config.aliyun_access_key_secret or "",
            region_id=config.aliyun_region_id,
            timeout_seconds=config.aliyun_http_timeout_seconds,
        )

    def exchange_access_token(self, access_token: str, request_id: str) -> OneClickAuthResult:
        try:
            response = self.client.call(
                "GetMobile",
                {
                    "AccessToken": access_token,
                    "OutId": request_id,
                },
            )
        except AliyunRpcError as exc:
            raise OneClickAuthExchangeError(
                message=f"Aliyun one-click login failed: {exc.code} {exc.message}",
                http_status=_map_exchange_http_status(exc.code),
                provider_code=exc.code,
            ) from exc

        dto = response.get("GetMobileResultDTO") or response.get("Data") or {}
        phone_number = dto.get("Mobile")
        passed = bool(phone_number)
        return OneClickAuthResult(
            provider=self.name,
            passed=passed,
            phone_number=str(phone_number).strip() if phone_number else None,
            provider_request_id=str(response.get("RequestId") or ""),
            provider_result=str(response.get("Code") or "OK"),
            raw_response=json.dumps(response, ensure_ascii=True),
        )


def build_one_click_auth_provider(config: AppConfig) -> OneClickAuthProvider:
    if config.one_click_provider == "mock":
        return MockOneClickAuthProvider(config)
    if config.one_click_provider == "aliyun":
        _validate_aliyun_one_click_config(config)
        return AliyunOneClickAuthProvider(config)
    raise ValueError(f"unsupported one-click provider: {config.one_click_provider}")


def _validate_aliyun_one_click_config(config: AppConfig) -> None:
    required = {
        "FUYAO_ALIYUN_ACCESS_KEY_ID": config.aliyun_access_key_id,
        "FUYAO_ALIYUN_ACCESS_KEY_SECRET": config.aliyun_access_key_secret,
    }
    missing = [name for name, value in required.items() if not value]
    if missing:
        raise ValueError(f"missing aliyun one-click config: {', '.join(missing)}")


def _map_exchange_http_status(provider_code: str) -> int:
    upper = provider_code.upper()
    if "ACCESS_TOKEN" in upper or "TOKEN" in upper or "PARAM" in upper:
        return 400
    if "THROTTLING" in upper or "LIMIT" in upper:
        return 429
    if "PERMISSION" in upper or "ACCESSKEY" in upper or "UNAUTHORIZED" in upper:
        return 500
    return 502
