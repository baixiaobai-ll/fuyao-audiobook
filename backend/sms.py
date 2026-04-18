from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any

from .aliyun_rpc import AliyunRpcClient, AliyunRpcError
from .config import AppConfig


class SmsSendError(RuntimeError):
    def __init__(self, message: str, http_status: int = 502, provider_code: str | None = None):
        super().__init__(message)
        self.http_status = http_status
        self.provider_code = provider_code


class SmsVerifyError(RuntimeError):
    def __init__(self, message: str, http_status: int = 502, provider_code: str | None = None):
        super().__init__(message)
        self.http_status = http_status
        self.provider_code = provider_code


@dataclass
class SmsSendResult:
    provider: str
    request_id: str
    provider_request_id: str | None = None
    provider_biz_id: str | None = None
    issued_code: str | None = None
    raw_response: str | None = None


@dataclass
class SmsVerifyResult:
    provider: str
    passed: bool
    provider_request_id: str | None = None
    provider_result: str | None = None
    raw_response: str | None = None


class SmsProvider:
    name = "base"
    stores_local_code = False

    def send_verification_code(
        self,
        phone: str,
        code: str,
        request_id: str,
        ttl_seconds: int,
    ) -> SmsSendResult:
        raise NotImplementedError

    def verify_code(self, phone: str, code: str, sms_record: Any) -> SmsVerifyResult:
        raise NotImplementedError


class MockSmsProvider(SmsProvider):
    name = "mock"
    stores_local_code = True

    def send_verification_code(
        self,
        phone: str,
        code: str,
        request_id: str,
        ttl_seconds: int,
    ) -> SmsSendResult:
        print(f"[mock-sms] phone={phone} code={code} request_id={request_id}")
        return SmsSendResult(
            provider=self.name,
            request_id=request_id,
            issued_code=code,
            raw_response=json.dumps({"mode": "mock", "ttlSeconds": ttl_seconds}, ensure_ascii=True),
        )

    def verify_code(self, phone: str, code: str, sms_record: Any) -> SmsVerifyResult:
        passed = sms_record["code"] == code
        return SmsVerifyResult(
            provider=self.name,
            passed=passed,
            provider_result="PASS" if passed else "REJECT",
        )


class AliyunSmsVerificationProvider(SmsProvider):
    name = "aliyun"
    stores_local_code = False

    def __init__(self, config: AppConfig):
        self.config = config
        self.client = AliyunRpcClient(
            endpoint=config.aliyun_endpoint,
            access_key_id=config.aliyun_access_key_id or "",
            access_key_secret=config.aliyun_access_key_secret or "",
            region_id=config.aliyun_region_id,
            timeout_seconds=config.aliyun_http_timeout_seconds,
        )

    def send_verification_code(
        self,
        phone: str,
        code: str,
        request_id: str,
        ttl_seconds: int,
    ) -> SmsSendResult:
        template_params = dict(self.config.aliyun_sms_template_extra_params)
        template_params[self.config.aliyun_sms_template_param_code_key] = "##code##"
        if self.config.aliyun_sms_template_param_minutes_key:
            template_params[self.config.aliyun_sms_template_param_minutes_key] = str(
                max(1, (self.config.aliyun_sms_validity_seconds + 59) // 60)
            )

        params = {
            "PhoneNumber": phone,
            "CountryCode": self.config.aliyun_country_code,
            "SignName": self.config.aliyun_sms_sign_name,
            "TemplateCode": self.config.aliyun_sms_template_code,
            "TemplateParam": json.dumps(template_params, ensure_ascii=False, separators=(",", ":")),
            "CodeLength": self.config.aliyun_sms_code_length,
            "CodeType": self.config.aliyun_sms_code_type,
            "ValidTime": self.config.aliyun_sms_validity_seconds,
            "Interval": self.config.aliyun_sms_interval_seconds,
            "DuplicatePolicy": self.config.aliyun_sms_duplicate_policy,
            "OutId": request_id,
            "AutoRetry": self.config.aliyun_sms_auto_retry,
            "SchemeName": self.config.aliyun_scheme_name,
        }
        if self.config.aliyun_sms_return_verify_code:
            params["ReturnVerifyCode"] = "true"

        try:
            response = self.client.call("SendSmsVerifyCode", params)
        except AliyunRpcError as exc:
            raise SmsSendError(
                message=f"Aliyun send sms failed: {exc.code} {exc.message}",
                http_status=_map_send_http_status(exc.code),
                provider_code=exc.code,
            ) from exc

        model = response.get("Model") or {}
        issued_code = model.get("VerifyCode")
        return SmsSendResult(
            provider=self.name,
            request_id=request_id,
            provider_request_id=str(model.get("RequestId") or response.get("RequestId") or ""),
            provider_biz_id=str(model.get("BizId") or ""),
            issued_code=str(issued_code) if issued_code else None,
            raw_response=json.dumps(response, ensure_ascii=True),
        )

    def verify_code(self, phone: str, code: str, sms_record: Any) -> SmsVerifyResult:
        params = {
            "PhoneNumber": phone,
            "CountryCode": self.config.aliyun_country_code,
            "VerifyCode": code,
            "OutId": sms_record["request_id"],
            "SchemeName": self.config.aliyun_scheme_name,
        }

        try:
            response = self.client.call("CheckSmsVerifyCode", params)
        except AliyunRpcError as exc:
            raise SmsVerifyError(
                message=f"Aliyun verify sms failed: {exc.code} {exc.message}",
                http_status=_map_verify_http_status(exc.code),
                provider_code=exc.code,
            ) from exc

        model = response.get("Model") or {}
        verify_result = (
            model.get("VerifyResult")
            or response.get("VerifyResult")
            or model.get("Result")
            or response.get("Result")
            or model.get("Pass")
        )
        normalized = str(verify_result).strip().upper()
        passed = normalized in {"PASS", "SUCCESS", "TRUE", "1"}

        return SmsVerifyResult(
            provider=self.name,
            passed=passed,
            provider_request_id=str(response.get("RequestId") or ""),
            provider_result=normalized or None,
            raw_response=json.dumps(response, ensure_ascii=True),
        )


def build_sms_provider(config: AppConfig) -> SmsProvider:
    if config.sms_provider == "mock":
        return MockSmsProvider()
    if config.sms_provider == "aliyun":
        _validate_aliyun_config(config)
        return AliyunSmsVerificationProvider(config)
    raise ValueError(f"unsupported sms provider: {config.sms_provider}")


def _validate_aliyun_config(config: AppConfig) -> None:
    required = {
        "FUYAO_ALIYUN_ACCESS_KEY_ID": config.aliyun_access_key_id,
        "FUYAO_ALIYUN_ACCESS_KEY_SECRET": config.aliyun_access_key_secret,
        "FUYAO_ALIYUN_SMS_SIGN_NAME": config.aliyun_sms_sign_name,
        "FUYAO_ALIYUN_SMS_TEMPLATE_CODE": config.aliyun_sms_template_code,
    }
    missing = [name for name, value in required.items() if not value]
    if missing:
        raise ValueError(f"missing aliyun sms config: {', '.join(missing)}")


def _map_send_http_status(provider_code: str) -> int:
    upper = provider_code.upper()
    if "MOBILE" in upper or "PHONE" in upper or "PARAM" in upper:
        return 400
    if "LIMIT" in upper or "FREQUENCY" in upper or "THROTTLE" in upper:
        return 429
    if "PERMISSION" in upper or "ACCESSKEY" in upper or "SIGNATURE" in upper:
        return 500
    return 502


def _map_verify_http_status(provider_code: str) -> int:
    upper = provider_code.upper()
    if "VERIFY_CODE" in upper or "CODE" in upper:
        return 401
    if "PARAM" in upper:
        return 400
    if "PERMISSION" in upper or "ACCESSKEY" in upper or "SIGNATURE" in upper:
        return 500
    return 502
