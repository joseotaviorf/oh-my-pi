import io
import json
from unittest.mock import MagicMock, patch
from urllib import error

import pytest

from dags.people.enrich_people_ai.spark_jobs.lib.llm_client import (
    DEFAULT_MODEL,
    DEFAULT_SECRET_KEY,
    DEFAULT_SECRET_SCOPE,
    LiteLLMClient,
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

    def test_default_model_is_bedrock_gpt_oss_not_openai_passthrough(self):
        """DBP-2138: ``openai/gpt-oss-20b`` hits api.openai.com and 404s.
        Databricks ``databricks-gpt-oss-20b`` is replaced by Bedrock Converse
        on the shared LiteLLM proxy (IRSA has AmazonBedrockLimitedAccess)."""
        assert DEFAULT_MODEL == "bedrock/converse/us.openai.gpt-oss-20b-1:0"
        client = LiteLLMClient(api_key="explicit-key")
        assert client.model == DEFAULT_MODEL

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

        client = LiteLLMClient(api_key="explicit-key")
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
        assert sent_payload["model"] == DEFAULT_MODEL

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

    @patch("dags.people.enrich_people_ai.spark_jobs.lib.llm_client.time.sleep")
    @patch("dags.people.enrich_people_ai.spark_jobs.lib.llm_client.request.urlopen")
    def test_complete_does_not_retry_http_404(self, mocked_urlopen, mocked_sleep):
        """DBP-2138: model_not_found 404 is not transient; retrying it 3x per
        invite hid a misconfigured LiteLLM model behind a successful Spark job."""
        mocked_urlopen.side_effect = _http_error(
            404,
            "Not Found",
            b'{"error":{"message":"The model `gpt-oss-20b` does not exist",'
            b'"code":"model_not_found"}}',
        )
        client = LiteLLMClient(api_key="explicit-key", max_retries=3)

        with pytest.raises(RuntimeError, match="model_not_found") as exc_info:
            client.complete("prompt text")

        assert mocked_urlopen.call_count == 1
        mocked_sleep.assert_not_called()
        assert "after 3 attempts" not in str(exc_info.value)

    @patch("dags.people.enrich_people_ai.spark_jobs.lib.llm_client.time.sleep")
    @patch("dags.people.enrich_people_ai.spark_jobs.lib.llm_client.request.urlopen")
    def test_complete_retries_http_429_then_succeeds(
        self, mocked_urlopen, mocked_sleep
    ):
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
        mocked_sleep.assert_called_once()
