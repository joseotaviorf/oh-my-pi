"""``datahub_graphql_post`` keeps existing return contract while adding structured logging."""

import io
import unittest
import urllib.error
from unittest import mock

from bietlejuice.governance.fairness_assessment.constants import (
    DATAHUB_FETCH_ERROR,
    DATAHUB_HTTP_ERROR,
    DATAHUB_URN_DIAG_OK,
)
from bietlejuice.governance.fairness_assessment.datahub_graphql import client


_URL = "https://datahub.example/api/graphql"
_QUERY = "query { health }"


class _FakeResponse:
    def __init__(self, body: bytes, status: int = 200):
        self._body = body
        self.status = status

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def read(self):
        return self._body

    def getcode(self):
        return self.status


class TestDatahubGraphqlPostReturnContract(unittest.TestCase):
    def test_200_with_json_returns_root_and_ok(self):
        resp = _FakeResponse(b'{"data": {"hello": "world"}}', status=200)
        with mock.patch("urllib.request.urlopen", return_value=resp):
            root, diag = client.datahub_graphql_post(_URL, "tok", _QUERY, {})
        self.assertEqual(root, {"data": {"hello": "world"}})
        self.assertEqual(diag, DATAHUB_URN_DIAG_OK)

    def test_non_200_returns_http_error(self):
        resp = _FakeResponse(b"oops", status=500)
        with mock.patch("urllib.request.urlopen", return_value=resp), mock.patch.object(
            client.LOGGER, "warning"
        ) as warn:
            root, diag = client.datahub_graphql_post(_URL, None, _QUERY, {})
        self.assertIsNone(root)
        self.assertEqual(diag, DATAHUB_HTTP_ERROR)
        warn.assert_called_once()
        self.assertIn("status=500", warn.call_args[0][0])

    def test_empty_body_returns_fetch_error(self):
        resp = _FakeResponse(b"   ", status=200)
        with mock.patch("urllib.request.urlopen", return_value=resp), mock.patch.object(
            client.LOGGER, "warning"
        ):
            root, diag = client.datahub_graphql_post(_URL, None, _QUERY, {})
        self.assertIsNone(root)
        self.assertEqual(diag, DATAHUB_FETCH_ERROR)

    def test_invalid_json_returns_fetch_error(self):
        resp = _FakeResponse(b"not-json", status=200)
        with mock.patch("urllib.request.urlopen", return_value=resp), mock.patch.object(
            client.LOGGER, "warning"
        ) as warn:
            root, diag = client.datahub_graphql_post(_URL, None, _QUERY, {})
        self.assertIsNone(root)
        self.assertEqual(diag, DATAHUB_FETCH_ERROR)
        warn.assert_called_once()
        self.assertIn("json_error", warn.call_args[0][0])

    def test_http_error_logs_status_reason_and_truncated_body(self):
        long_body = ("error-detail " * 100).encode("utf-8")
        http_error = urllib.error.HTTPError(
            url=_URL,
            code=401,
            msg="Unauthorized",
            hdrs=None,  # type: ignore[arg-type]
            fp=io.BytesIO(long_body),
        )
        with mock.patch(
            "urllib.request.urlopen", side_effect=http_error
        ), mock.patch.object(client.LOGGER, "warning") as warn:
            root, diag = client.datahub_graphql_post(_URL, "tok", _QUERY, {})
        self.assertIsNone(root)
        self.assertEqual(diag, DATAHUB_HTTP_ERROR)
        warn.assert_called_once()
        message = warn.call_args[0][0]
        self.assertIn("http_error", message)
        self.assertIn("status=401", message)
        self.assertIn("Unauthorized", message)
        # Body present in the log but truncated to the configured cap.
        self.assertIn("body=", message)
        body_segment = message.split("body=", 1)[1]
        self.assertLessEqual(len(body_segment), client._HTTP_ERROR_BODY_MAX_CHARS)

    def test_timeout_returns_fetch_error_and_logs(self):
        with mock.patch(
            "urllib.request.urlopen", side_effect=TimeoutError("slow")
        ), mock.patch.object(client.LOGGER, "warning") as warn:
            root, diag = client.datahub_graphql_post(_URL, None, _QUERY, {})
        self.assertIsNone(root)
        self.assertEqual(diag, DATAHUB_FETCH_ERROR)
        warn.assert_called_once()
        self.assertIn("timeout", warn.call_args[0][0])

    def test_url_error_returns_fetch_error_and_logs(self):
        url_error = urllib.error.URLError("name resolution failed")
        with mock.patch(
            "urllib.request.urlopen", side_effect=url_error
        ), mock.patch.object(client.LOGGER, "warning") as warn:
            root, diag = client.datahub_graphql_post(_URL, None, _QUERY, {})
        self.assertIsNone(root)
        self.assertEqual(diag, DATAHUB_FETCH_ERROR)
        warn.assert_called_once()
        self.assertIn("url_error", warn.call_args[0][0])

    def test_os_error_returns_fetch_error_and_logs(self):
        with mock.patch(
            "urllib.request.urlopen", side_effect=OSError("conn refused")
        ), mock.patch.object(client.LOGGER, "warning") as warn:
            root, diag = client.datahub_graphql_post(_URL, None, _QUERY, {})
        self.assertIsNone(root)
        self.assertEqual(diag, DATAHUB_FETCH_ERROR)
        warn.assert_called_once()
        self.assertIn("os_error", warn.call_args[0][0])


if __name__ == "__main__":
    unittest.main()
