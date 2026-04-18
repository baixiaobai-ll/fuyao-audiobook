from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
from datetime import datetime, timezone
from typing import Any
from urllib.parse import quote, urlencode
import urllib.request


class AliyunRpcError(RuntimeError):
    def __init__(self, code: str, message: str, request_id: str | None = None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.request_id = request_id


def percent_encode(value: Any) -> str:
    return quote(str(value), safe="~")


class AliyunRpcClient:
    version = "2017-05-25"

    def __init__(
        self,
        endpoint: str,
        access_key_id: str,
        access_key_secret: str,
        region_id: str,
        timeout_seconds: int = 10,
    ):
        self.endpoint = endpoint.rstrip("/")
        self.access_key_id = access_key_id
        self.access_key_secret = access_key_secret
        self.region_id = region_id
        self.timeout_seconds = timeout_seconds

    def call(self, action: str, extra_params: dict[str, Any]) -> dict[str, Any]:
        params: dict[str, Any] = {
            "Action": action,
            "Format": "JSON",
            "Version": self.version,
            "AccessKeyId": self.access_key_id,
            "SignatureMethod": "HMAC-SHA1",
            "Timestamp": datetime.now(timezone.utc).replace(microsecond=0).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "SignatureVersion": "1.0",
            "SignatureNonce": secrets.token_hex(16),
            "RegionId": self.region_id,
        }
        for key, value in extra_params.items():
            if value is None or value == "":
                continue
            params[key] = value

        params["Signature"] = self._sign("POST", params)
        body = urlencode(params).encode("utf-8")
        request = urllib.request.Request(
            self.endpoint,
            data=body,
            method="POST",
            headers={"Content-Type": "application/x-www-form-urlencoded; charset=utf-8"},
        )

        try:
            with urllib.request.urlopen(request, timeout=self.timeout_seconds) as response:
                raw = response.read().decode("utf-8")
        except urllib.error.HTTPError as exc:
            raw = exc.read().decode("utf-8", errors="replace")
            raise AliyunRpcError("HTTP_ERROR", raw) from exc
        except Exception as exc:
            raise AliyunRpcError("NETWORK_ERROR", str(exc)) from exc

        try:
            data = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise AliyunRpcError("INVALID_RESPONSE", raw) from exc

        code = str(data.get("Code", ""))
        if code and code != "OK":
            raise AliyunRpcError(
                code=code,
                message=str(data.get("Message", code)),
                request_id=data.get("RequestId"),
            )
        return data

    def _sign(self, method: str, params: dict[str, Any]) -> str:
        items = sorted((percent_encode(k), percent_encode(v)) for k, v in params.items())
        canonicalized = "&".join(f"{key}={value}" for key, value in items)
        string_to_sign = f"{method}&%2F&{percent_encode(canonicalized)}"
        digest = hmac.new(
            f"{self.access_key_secret}&".encode("utf-8"),
            string_to_sign.encode("utf-8"),
            hashlib.sha1,
        ).digest()
        return base64.b64encode(digest).decode("utf-8")
