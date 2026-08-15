from __future__ import annotations

import os
import unittest
from unittest.mock import patch

from backend.config import load_config


CONFIG_KEYS = {
    "FUYAO_ENVIRONMENT",
    "FUYAO_ENV_FILE",
    "FUYAO_ONE_CLICK_PROVIDER",
    "FUYAO_SMS_PROVIDER",
}


class RuntimeConfigTests(unittest.TestCase):
    def _clean_environment(self) -> dict[str, str]:
        return {key: value for key, value in os.environ.items() if key not in CONFIG_KEYS}

    def test_development_allows_mock_providers(self) -> None:
        env = self._clean_environment()
        env["FUYAO_ENVIRONMENT"] = "development"
        env["FUYAO_ENV_FILE"] = "/path/that/does/not/exist"
        with patch.dict(os.environ, env, clear=True):
            config = load_config()
        self.assertEqual(config.one_click_provider, "mock")
        self.assertEqual(config.sms_provider, "mock")

    def test_production_rejects_mock_authentication(self) -> None:
        env = self._clean_environment()
        env["FUYAO_ENVIRONMENT"] = "production"
        env["FUYAO_ENV_FILE"] = "/path/that/does/not/exist"
        env["FUYAO_ONE_CLICK_PROVIDER"] = "mock"
        env["FUYAO_SMS_PROVIDER"] = "aliyun"
        with patch.dict(os.environ, env, clear=True):
            with self.assertRaisesRegex(ValueError, "mock authentication is disabled"):
                load_config()


if __name__ == "__main__":
    unittest.main()
