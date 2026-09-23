"""HTTP client for QuintoAndar's internal LiteLLM OpenAI-compatible gateway.

Provides a minimal ``/chat/completions`` wrapper used by People AI Spark jobs on
EMR. Authentication uses the Databricks ``people`` secret scope by default; tests
and local runs can inject an explicit API key via the constructor.
"""

from __future__ import annotations

import json
import os
import time
from typing import Any, Dict, Optional
from urllib import error, request

from bietlejuice.base.spark import BaseDBUtils

DEFAULT_BASE_URL = "https://litellm.apps.shared-prd.habitat.zone/v1"
# Shared LiteLLM catalog (chat mode).
DEFAULT_MODEL = "vertex_ai/claude-sonnet-4-5"
DEFAULT_SECRET_SCOPE = "people"
DEFAULT_SECRET_KEY = "PEOPLE_DATA_LITELLM_KEY"
DEFAULT_MAX_RETRIES = 3
DEFAULT_TIMEOUT_SECONDS = 180
# 4096 truncated Teva JSON on EMR (finish_reason=length → unparseable object).
# Sonnet 4.5 catalog max is 64K.
DEFAULT_MAX_TOKENS = 16384
# Match the Datahub LiteLLM client: retry rate limits and gateway failures only.
_RETRYABLE_HTTP_STATUS = frozenset({429, 502, 503, 504})
_HTTP_ERROR_BODY_MAX_CHARS = 500
_PREVIEW_MAX_CHARS = 1500


def preview_llm_text(value: Optional[object]) -> str:
    """Collapse whitespace and truncate for Airflow/EMR warning lines."""
    if value is None:
        return ""
    collapsed = " ".join(str(value).split())
    if len(collapsed) > _PREVIEW_MAX_CHARS:
        return collapsed[:_PREVIEW_MAX_CHARS] + "..."
    return collapsed


class LiteLLMClient:
    """OpenAI-compatible chat client for the internal LiteLLM proxy.

    Sends JSON POST requests to ``{base_url}/chat/completions`` with bearer auth,
    configurable temperature and ``max_tokens`` (default 16384). Retries only
    transient failures (429, 502, 503, 504, network, timeout, invalid JSON) with
    exponential backoff capped at 10 seconds. Non-transient HTTP errors such as
    404 are raised immediately so a misconfigured model cannot look like success.
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
        max_tokens: Optional[int] = None,
        temperature: float = 0.2,
    ) -> None:
        """Initialize gateway URL, model name, and credentials.

        Resolution order for ``base_url`` and ``model``: explicit argument, then
        ``LITELLM_BASE_URL`` / ``LITELLM_MODEL`` environment variables, then module
        defaults. When ``api_key`` is omitted, reads ``secret_key`` from
        ``dbutils.secrets`` in ``secret_scope`` via :class:`BaseDBUtils`.

        Args:
            base_url: LiteLLM root URL without trailing slash; defaults to production
                shared gateway unless ``LITELLM_BASE_URL`` is set.
            model: Model id passed in the JSON body (e.g.
                ``vertex_ai/claude-sonnet-4-5``).
            api_key: Bearer token; when ``None``, loaded from Databricks secrets.
            secret_scope: Databricks secret scope name for API key lookup.
            secret_key: Secret key name within ``secret_scope``.
            max_retries: Maximum POST attempts before raising :class:`RuntimeError`.
            timeout_seconds: Per-request socket timeout for ``urlopen``.
            max_tokens: ``max_tokens`` field sent to the chat completions API.
                Resolution: argument, then ``LITELLM_MAX_TOKENS``, then
                :data:`DEFAULT_MAX_TOKENS`.
            temperature: Sampling temperature sent to the chat completions API.
        """
        self.base_url = (
            base_url or os.environ.get("LITELLM_BASE_URL") or DEFAULT_BASE_URL
        ).rstrip("/")
        self.model = model or os.environ.get("LITELLM_MODEL") or DEFAULT_MODEL
        self.max_retries = max_retries
        self.timeout_seconds = timeout_seconds
        env_max_tokens = os.environ.get("LITELLM_MAX_TOKENS")
        if max_tokens is not None:
            self.max_tokens = max_tokens
        elif env_max_tokens:
            self.max_tokens = int(env_max_tokens)
        else:
            self.max_tokens = DEFAULT_MAX_TOKENS
        self.temperature = temperature
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
            RuntimeError: When the HTTP layer fails (non-retryable errors fail
                immediately; retryable errors fail after all retries), the response
                has no ``choices``, the first choice has no ``message.content``,
                or ``finish_reason`` is ``length`` (truncated before valid JSON).
        """
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})
        payload: Dict[str, Any] = {
            "model": self.model,
            "messages": messages,
            "max_tokens": self.max_tokens,
            "temperature": self.temperature,
        }
        response_json = self._post_json("/chat/completions", payload)
        choices = response_json.get("choices") or []
        if not choices:
            raise RuntimeError("LiteLLM response missing choices")
        choice = choices[0]
        finish_reason = choice.get("finish_reason")
        message = choice.get("message") or {}
        content = message.get("content")
        if finish_reason == "length":
            preview = preview_llm_text(content)
            raise RuntimeError(
                "LiteLLM response truncated (finish_reason='length') before "
                f"a complete reply. preview={preview!r}"
            )
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
            RuntimeError: On a non-retryable HTTP error, or after ``max_retries``
                failed attempts due to retryable HTTP errors, network errors,
                timeouts, or invalid JSON in the response body.
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
                if not _is_retryable(exc) or attempt >= self.max_retries:
                    break
                time.sleep(min(2**attempt, 10))
        raise RuntimeError(_format_request_failure(self.max_retries, last_error))


def _is_retryable(exc: Exception) -> bool:
    """Return True when the failure is worth retrying (rate limit, gateway, network)."""
    if isinstance(exc, error.HTTPError):
        return exc.code in _RETRYABLE_HTTP_STATUS
    return isinstance(exc, (error.URLError, TimeoutError, json.JSONDecodeError))


def _http_error_detail(exc: error.HTTPError) -> str:
    """Include status, reason, and a truncated response body for Airflow logs."""
    body = ""
    try:
        raw = exc.read()
        if raw:
            body = raw.decode("utf-8", errors="replace").strip()
    except Exception:
        body = ""
    if len(body) > _HTTP_ERROR_BODY_MAX_CHARS:
        body = body[:_HTTP_ERROR_BODY_MAX_CHARS] + "..."
    detail = f"HTTP Error {exc.code}: {exc.reason}"
    if body:
        return f"{detail}: {body}"
    return detail


def _format_request_failure(max_retries: int, last_error: Optional[Exception]) -> str:
    if isinstance(last_error, error.HTTPError):
        detail = _http_error_detail(last_error)
        if last_error.code in _RETRYABLE_HTTP_STATUS:
            return f"LiteLLM request failed after {max_retries} attempts: {detail}"
        return f"LiteLLM request failed: {detail}"
    return f"LiteLLM request failed after {max_retries} attempts: {last_error}"
