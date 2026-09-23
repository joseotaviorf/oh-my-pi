import io
import json
from unittest.mock import MagicMock, patch
from urllib import error

import pytest

from dags.people.enrich_people_ai.spark_jobs.lib.llm_client import (
    DEFAULT_MAX_TOKENS,
    DEFAULT_SECRET_KEY,
    DEFAULT_SECRET_SCOPE,
    LiteLLMClient,
    preview_llm_text,
)


def _http_error(code, reason, body=b""):
    return error.HTTPError(
        url="https://litellm.example/v1/chat/completions",
        code=code,
        msg=reason,
        hdrs=None,
        fp=io.BytesIO(body),
    )


class TestLiteLLMClient:
    """Unit tests for the generic LiteLLM-compatible HTTP client."""

    def test_uses_explicit_api_key_without_calling_dbutils(self):
        """An explicit ``api_key`` bypasses the secret lookup entirely."""
        client = LiteLLMClient(api_key="explicit-key")

        assert client.api_key == "explicit-key"

    @patch("dags.people.enrich_people_ai.spark_jobs.lib.llm_client.BaseDBUtils")
    def test_resolves_api_key_from_secrets_when_not_provided(
        self, mocked_base_db_utils
    ):
        """Without an explicit key, the client resolves it via dbutils secrets,
        using the default scope and the ``PEOPLE_DATA_LITELLM_KEY`` secret name."""
        mocked_secrets = MagicMock()
        mocked_secrets.get.return_value = "secret-from-vault"
        mocked_base_db_utils.return_value.get_dbutils.return_value.secrets = (
            mocked_secrets
        )

        client = LiteLLMClient()

        assert client.api_key == "secret-from-vault"
        mocked_secrets.get.assert_called_once_with(
            DEFAULT_SECRET_SCOPE, DEFAULT_SECRET_KEY
        )

    def test_default_secret_key_matches_aws_secrets_manager_name(self):
        """Regression: the default secret key must match the plain-string
        secret provisioned in AWS Secrets Manager for EMR jobs, not the old
        Databricks-scope placeholder name."""
        assert DEFAULT_SECRET_KEY == "PEOPLE_DATA_LITELLM_KEY"

    def test_constructor_model_overrides_default(self):
        """An explicit ``model`` is stored as-is; tests do not pin the catalog default."""
        client = LiteLLMClient(
            api_key="explicit-key",
            model="catalog/test-model",
            temperature=0.7,
        )

        assert client.model == "catalog/test-model"

    def test_litellm_model_env_overrides_default(self, monkeypatch):
        """``LITELLM_MODEL`` wins over the module default when ``model`` is omitted."""
        monkeypatch.setenv("LITELLM_MODEL", "catalog/from-env")
        client = LiteLLMClient(api_key="explicit-key")

        assert client.model == "catalog/from-env"

    @patch("dags.people.enrich_people_ai.spark_jobs.lib.llm_client.request.urlopen")
    def test_complete_returns_message_content(self, mocked_urlopen):
        """``complete`` posts a chat-completion payload and returns the first
        choice's message content, stripped of surrounding whitespace."""
        response_body = json.dumps(
            {"choices": [{"message": {"content": "  generated text  "}}]}
        ).encode("utf-8")
        mocked_response = MagicMock()
        mocked_response.read.return_value = response_body
        mocked_urlopen.return_value.__enter__.return_value = mocked_response

        client = LiteLLMClient(
            api_key="explicit-key",
            model="catalog/test-model",
            temperature=0.7,
        )
        result = client.complete("prompt text", system_prompt="system context")

        assert result == "generated text"
        sent_request = mocked_urlopen.call_args[0][0]
        sent_payload = json.loads(sent_request.data.decode("utf-8"))
        assert sent_payload["messages"][0] == {
            "role": "system",
            "content": "system context",
        }
        assert sent_payload["messages"][1] == {
            "role": "user",
            "content": "prompt text",
        }
        assert sent_payload["model"] == "catalog/test-model"
        assert sent_payload["temperature"] == 0.7
        assert sent_payload["max_tokens"] == DEFAULT_MAX_TOKENS

    def test_default_max_tokens_is_above_previous_truncation_ceiling(self):
        """4096 was too small for Teva JSON; the default must stay above that."""
        assert DEFAULT_MAX_TOKENS == 16384

    def test_litellm_max_tokens_env_overrides_default(self, monkeypatch):
        monkeypatch.setenv("LITELLM_MAX_TOKENS", "32000")
        client = LiteLLMClient(api_key="explicit-key")
        assert client.max_tokens == 32000

    @patch("dags.people.enrich_people_ai.spark_jobs.lib.llm_client.request.urlopen")
    def test_complete_raises_when_finish_reason_is_length(self, mocked_urlopen):
        """Truncated replies must fail closed instead of looking like prose JSON."""
        response_body = json.dumps(
            {
                "choices": [
                    {
                        "finish_reason": "length",
                        "message": {"content": '{"executive_summary": "cut off'},
                    }
                ]
            }
        ).encode("utf-8")
        mocked_response = MagicMock()
        mocked_response.read.return_value = response_body
        mocked_urlopen.return_value.__enter__.return_value = mocked_response

        client = LiteLLMClient(api_key="explicit-key", model="catalog/test-model")
        with pytest.raises(RuntimeError, match="finish_reason='length'"):
            client.complete("prompt text")

    def test_preview_llm_text_collapses_whitespace_and_truncates(self):
        assert preview_llm_text("a\n\nb") == "a b"
        long_text = "x" * 1600
        preview = preview_llm_text(long_text)
        assert preview.endswith("...")
        assert len(preview) == 1500 + 3

    @patch("dags.people.enrich_people_ai.spark_jobs.lib.llm_client.request.urlopen")
    def test_complete_raises_when_response_has_no_choices(self, mocked_urlopen):
        """A LiteLLM response missing ``choices`` is treated as a hard failure
        rather than silently returning an empty summary."""
        response_body = json.dumps({"choices": []}).encode("utf-8")
        mocked_response = MagicMock()
        mocked_response.read.return_value = response_body
        mocked_urlopen.return_value.__enter__.return_value = mocked_response

        client = LiteLLMClient(api_key="explicit-key", max_retries=1)

        with pytest.raises(RuntimeError, match="missing choices"):
            client.complete("prompt text")

    @patch("dags.people.enrich_people_ai.spark_jobs.lib.llm_client.time")
    @patch("dags.people.enrich_people_ai.spark_jobs.lib.llm_client.request.urlopen")
    def test_complete_does_not_retry_http_404(self, mocked_urlopen, mocked_time):
        """HTTP 404 is not retryable; the client raises on the first attempt."""
        mocked_urlopen.side_effect = _http_error(
            404,
            "Not Found",
            b'{"error":{"message":"The model `unknown-model` does not exist",'
            b'"code":"model_not_found"}}',
        )
        client = LiteLLMClient(api_key="explicit-key", max_retries=3)

        with pytest.raises(RuntimeError, match="model_not_found") as exc_info:
            client.complete("prompt text")

        assert mocked_urlopen.call_count == 1
        mocked_time.sleep.assert_not_called()
        assert "after 3 attempts" not in str(exc_info.value)

    @patch("dags.people.enrich_people_ai.spark_jobs.lib.llm_client.time")
    @patch("dags.people.enrich_people_ai.spark_jobs.lib.llm_client.request.urlopen")
    def test_complete_retries_http_429_then_succeeds(self, mocked_urlopen, mocked_time):
        """Rate limits are retried, then a later success is returned."""
        success_body = json.dumps({"choices": [{"message": {"content": "ok"}}]}).encode(
            "utf-8"
        )
        success_response = MagicMock()
        success_response.read.return_value = success_body
        success_cm = MagicMock()
        success_cm.__enter__.return_value = success_response
        mocked_urlopen.side_effect = [
            _http_error(429, "Too Many Requests", b'{"error":"rate"}'),
            success_cm,
        ]
        client = LiteLLMClient(api_key="explicit-key", max_retries=3)

        assert client.complete("prompt text") == "ok"
        assert mocked_urlopen.call_count == 2
        mocked_time.sleep.assert_called_once()
