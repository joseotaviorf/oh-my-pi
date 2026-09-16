"""HTTP client for QuintoAndar's internal LiteLLM OpenAI-compatible gateway.

Provides a minimal ``/chat/completions`` wrapper used by People AI Spark jobs on
Databricks and EMR. Authentication uses the Databricks ``people`` secret scope by
default; tests and local runs can inject an explicit API key via the constructor.
"""

from __future__ import annotations

import json
import os
import time
from typing import Any, Dict, Optional
from urllib import error, request

from bietlejuice.base.spark import BaseDBUtils

DEFAULT_BASE_URL = "https://litellm.apps.shared-prd.habitat.zone/v1"
DEFAULT_MODEL = "openai/gpt-oss-20b"
DEFAULT_SECRET_SCOPE = "people"
DEFAULT_SECRET_KEY = "PEOPLE_DATA_LITELLM_KEY"
DEFAULT_MAX_RETRIES = 3
DEFAULT_TIMEOUT_SECONDS = 120
DEFAULT_MAX_TOKENS = 4096


class LiteLLMClient:
    """OpenAI-compatible chat client for the internal LiteLLM proxy.

    Sends JSON POST requests to ``{base_url}/chat/completions`` with bearer auth,
    fixed low temperature (0.2), and configurable ``max_tokens``. Retries transient
    network and HTTP failures with exponential backoff capped at 10 seconds.
    """

    def __init__(
        self,
        base_url: Optional[str] = None,
        model: Optional[str] = None,
        api_key: Optional[str] = None,
        secret_scope: str = DEFAULT_SECRET_SCOPE,
        secret_key: str = DEFAULT_SECRET_KEY,
        max_retries: int = DEFAULT_MAX_RETRIES,
        timeout_seconds: int = DEFAULT_TIMEOUT_SECONDS,
        max_tokens: int = DEFAULT_MAX_TOKENS,
    ) -> None:
        """Initialize gateway URL, model name, and credentials.

        Resolution order for ``base_url`` and ``model``: explicit argument, then
        ``LITELLM_BASE_URL`` / ``LITELLM_MODEL`` environment variables, then module
        defaults. When ``api_key`` is omitted, reads ``secret_key`` from
        ``dbutils.secrets`` in ``secret_scope`` via :class:`BaseDBUtils`.

        Args:
            base_url: LiteLLM root URL without trailing slash; defaults to production
                shared gateway unless ``LITELLM_BASE_URL`` is set.
            model: Model id passed in the JSON body (e.g. ``openai/gpt-oss-20b``).
            api_key: Bearer token; when ``None``, loaded from Databricks secrets.
            secret_scope: Databricks secret scope name for API key lookup.
            secret_key: Secret key name within ``secret_scope``.
            max_retries: Maximum POST attempts before raising :class:`RuntimeError`.
            timeout_seconds: Per-request socket timeout for ``urlopen``.
            max_tokens: ``max_tokens`` field sent to the chat completions API.
        """
        self.base_url = (
            base_url or os.environ.get("LITELLM_BASE_URL") or DEFAULT_BASE_URL
        ).rstrip("/")
        self.model = model or os.environ.get("LITELLM_MODEL") or DEFAULT_MODEL
        self.max_retries = max_retries
        self.timeout_seconds = timeout_seconds
        self.max_tokens = max_tokens
        if api_key is not None:
            self.api_key = api_key
        else:
            self.api_key = (
                BaseDBUtils().get_dbutils().secrets.get(secret_scope, secret_key)
            )

    def complete(self, prompt: str, system_prompt: Optional[str] = None) -> str:
        """Request a single chat completion and return assistant text.

        Builds a two-message (optional system + user) payload, posts to
        ``/chat/completions``, and returns the first choice's ``message.content``
        stripped of leading/trailing whitespace.

        Args:
            prompt: User message body (may be long structured text).
            system_prompt: Optional system message prepended when not ``None``.

        Returns:
            Non-empty assistant content string from the first choice.

        Raises:
            RuntimeError: When the HTTP layer fails after all retries, the response
                has no ``choices``, or the first choice has no ``message.content``.
        """
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})
        payload: Dict[str, Any] = {
            "model": self.model,
            "messages": messages,
            "max_tokens": self.max_tokens,
            "temperature": 0.2,
        }
        response_json = self._post_json("/chat/completions", payload)
        choices = response_json.get("choices") or []
        if not choices:
            raise RuntimeError("LiteLLM response missing choices")
        message = choices[0].get("message") or {}
        content = message.get("content")
        if not content:
            raise RuntimeError("LiteLLM response missing message content")
        return str(content).strip()

    def _post_json(self, path: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        """POST a JSON body to ``base_url + path`` and decode the JSON response.

        Args:
            path: Path segment starting with ``/`` (e.g. ``/chat/completions``).
            payload: Serializable dict sent as the request body.

        Returns:
            Parsed JSON response as a dict.

        Raises:
            RuntimeError: After ``max_retries`` failed attempts due to HTTP errors,
                network errors, timeouts, or invalid JSON in the response body.
        """
        body = json.dumps(payload).encode("utf-8")
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        url = f"{self.base_url}{path}"
        last_error: Optional[Exception] = None
        for attempt in range(1, self.max_retries + 1):
            try:
                req = request.Request(url, data=body, headers=headers, method="POST")
                with request.urlopen(req, timeout=self.timeout_seconds) as resp:
                    return json.loads(resp.read().decode("utf-8"))
            except (
                error.HTTPError,
                error.URLError,
                TimeoutError,
                json.JSONDecodeError,
            ) as exc:
                last_error = exc
                if attempt >= self.max_retries:
                    break
                time.sleep(min(2**attempt, 10))
        raise RuntimeError(
            f"LiteLLM request failed after {self.max_retries} attempts: {last_error}"
        )
