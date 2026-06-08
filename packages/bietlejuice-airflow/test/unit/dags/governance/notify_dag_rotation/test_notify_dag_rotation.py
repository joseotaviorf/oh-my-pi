"""Unit tests for platform notify_dag_rotation DAG logic and structure."""

from __future__ import annotations

import json
from unittest import mock

import pytest

from dags.governance.notify_dag_rotation.notify_dag_rotation import (
    _OWNER_DISPLAY_NAME_MAP,
    JIRA_OPS_SCHEDULE_ID,
    _clean_dag_owner,
    _count_voice_wakeups,
    _environment_suffix,
    _fetch_dei_issues,
    _get_oncall_recipients,
    _get_schedule_timeline,
    _get_user_display,
    _is_gchat_webhook,
    _parse_rfc3339,
    _resolve_issue_owners,
    _wrap_for_gchat,
    dag,
    notify_dag_rotation,
)

_MOCK_WEBHOOK_KEYS = {
    "data_quality": "GCHAT_DATA_QUALITY_FORNO_WEBHOOK",
    "stale_dag": "GCHAT_STALE_DAG_WEBHOOK",
    "dag_rotation": "NOTIFICATION_HUB_DAG_ROTATION_WEBHOOK",
    "iam_alerts": "NOTIFICATION_HUB_IAM_ALERTS_WEBHOOK",
}

_MOCK_JIRA_SECRET = json.dumps(
    {
        "username": "user@example.com",
        "token": "token123",
        "server": "https://quintoandar.atlassian.net",
    }
)

_MOCK_JIRA_OPS_SECRET = json.dumps(
    {
        "username": "ops_user@example.com",
        "token": "ops_token123",
        "server": "https://api.atlassian.com",
        "cloud_id": "test-cloud-id",
    }
)


class TestParseRfc3339:
    @pytest.mark.parametrize(
        "input_str,expected_hour",
        [
            ("2026-05-04T03:00:00Z", 3),
            ("2026-05-04T03:00:00.000Z", 3),
            ("2026-05-05T00:00:00.123456Z", 0),
        ],
    )
    def test_parses_valid_rfc3339_strings(self, input_str, expected_hour):
        result = _parse_rfc3339(input_str)
        assert result.hour == expected_hour
        assert result.tzinfo is not None

    def test_raises_on_invalid_format(self):
        with pytest.raises(ValueError):
            _parse_rfc3339("not-a-date")


class TestCleanDagOwner:
    @pytest.mark.parametrize(
        "raw,expected",
        [
            ("airflow, Data People", "Data People"),
            ("Data People ,airflow", "Data People"),
            ("Data People", "Data People"),
            ("", ""),
        ],
    )
    def test_strips_airflow_pseudo_owner(self, raw, expected):
        assert _clean_dag_owner(raw) == expected


class TestOwnerDisplayNameMap:
    def test_known_owners_are_mapped(self):
        assert _OWNER_DISPLAY_NAME_MAP["Data ForRent"] == "Data For Rent"
        assert _OWNER_DISPLAY_NAME_MAP["MLOps Team"] == "MLOps"
        assert _OWNER_DISPLAY_NAME_MAP["Data SS"] == "Data S&S"

    def test_unknown_owner_not_in_map(self):
        assert "Unknown Team" not in _OWNER_DISPLAY_NAME_MAP


class TestEnvironmentSuffix:
    def test_forno_suffix(self, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "forno")
        assert _environment_suffix() == " · FORNO"

    def test_prod_suffix(self, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "prod")
        assert _environment_suffix() == " · PROD"

    def test_empty_for_other_or_unset(self, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "local")
        assert _environment_suffix() == ""
        monkeypatch.delenv("ENVIRONMENT", raising=False)
        assert _environment_suffix() == ""


class TestFetchDeiIssues:
    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.post")
    def test_returns_parsed_issues(self, mock_post):
        mock_resp = mock.MagicMock()
        mock_resp.raise_for_status = mock.MagicMock()
        mock_resp.json.return_value = {
            "issues": [
                {
                    "id": "10001",
                    "key": "DEI-42",
                    "fields": {
                        "summary": "domain.failing_dag",
                        "created": "2026-05-05T01:00:00Z",
                        "customfield_12078": {"value": "Data People"},
                    },
                }
            ],
            "isLast": True,
        }
        mock_post.return_value = mock_resp
        from requests.auth import HTTPBasicAuth

        auth = HTTPBasicAuth("u", "t")
        issues = _fetch_dei_issues(auth, "2026-05-04", "2026-05-05")

        assert len(issues) == 1
        assert issues[0]["key"] == "DEI-42"
        assert issues[0]["incident_owner"] == "Data People"
        assert issues[0]["summary"] == "domain.failing_dag"

    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.post")
    def test_returns_none_incident_owner_when_field_missing(self, mock_post):
        mock_resp = mock.MagicMock()
        mock_resp.raise_for_status = mock.MagicMock()
        mock_resp.json.return_value = {
            "issues": [
                {
                    "id": "10002",
                    "key": "DEI-43",
                    "fields": {
                        "summary": "domain.another_dag",
                        "created": "2026-05-05T02:00:00Z",
                        "customfield_12078": None,
                    },
                }
            ],
            "isLast": True,
        }
        mock_post.return_value = mock_resp
        from requests.auth import HTTPBasicAuth

        issues = _fetch_dei_issues(HTTPBasicAuth("u", "t"), "2026-05-04", "2026-05-05")

        assert issues[0]["incident_owner"] is None

    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.post")
    def test_returns_empty_list_when_no_issues(self, mock_post):
        mock_resp = mock.MagicMock()
        mock_resp.raise_for_status = mock.MagicMock()
        mock_resp.json.return_value = {"issues": [], "isLast": True}
        mock_post.return_value = mock_resp
        from requests.auth import HTTPBasicAuth

        result = _fetch_dei_issues(HTTPBasicAuth("u", "t"), "2026-05-04", "2026-05-05")
        assert result == []

    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.post")
    def test_paginates_using_next_page_token(self, mock_post):
        page1 = mock.MagicMock()
        page1.raise_for_status = mock.MagicMock()
        page1.json.return_value = {
            "issues": [
                {
                    "id": "10001",
                    "key": "DEI-1",
                    "fields": {
                        "summary": "dag1",
                        "created": "2026-05-05T01:00:00Z",
                        "customfield_12078": None,
                    },
                }
            ],
            "isLast": False,
            "nextPageToken": "cursor-abc",
        }
        page2 = mock.MagicMock()
        page2.raise_for_status = mock.MagicMock()
        page2.json.return_value = {
            "issues": [
                {
                    "id": "10002",
                    "key": "DEI-2",
                    "fields": {
                        "summary": "dag2",
                        "created": "2026-05-05T02:00:00Z",
                        "customfield_12078": None,
                    },
                }
            ],
            "isLast": True,
        }
        mock_post.side_effect = [page1, page2]
        from requests.auth import HTTPBasicAuth

        issues = _fetch_dei_issues(HTTPBasicAuth("u", "t"), "2026-05-04", "2026-05-05")

        assert len(issues) == 2
        assert mock_post.call_count == 2
        second_call_body = mock_post.call_args_list[1][1]["json"]
        assert second_call_body["nextPageToken"] == "cursor-abc"


class TestResolveIssueOwners:
    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.put")
    def test_assigns_owner_from_dag_owner_map(self, mock_put):
        mock_put.return_value = mock.MagicMock(status_code=204)
        from requests.auth import HTTPBasicAuth

        issues = [{"key": "DEI-1", "summary": "domain.my_dag", "incident_owner": None}]
        dag_owner_map = {"domain.my_dag": "Data People"}

        result = _resolve_issue_owners(issues, dag_owner_map, HTTPBasicAuth("u", "t"))

        assert result[0]["owner"] == "Data People"
        mock_put.assert_called_once()

    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.put")
    def test_falls_back_to_ae_all_when_dag_not_found(self, mock_put):
        from requests.auth import HTTPBasicAuth

        issues = [{"key": "DEI-2", "summary": "unknown.dag", "incident_owner": None}]
        result = _resolve_issue_owners(issues, {}, HTTPBasicAuth("u", "t"))

        assert result[0]["owner"] == "AE All"
        mock_put.assert_not_called()

    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.put")
    def test_preserves_existing_incident_owner(self, mock_put):
        from requests.auth import HTTPBasicAuth

        issues = [
            {
                "key": "DEI-3",
                "summary": "domain.dag",
                "incident_owner": "Data Fintech",
            }
        ]
        result = _resolve_issue_owners(issues, {}, HTTPBasicAuth("u", "t"))

        assert result[0]["owner"] == "Data Fintech"
        mock_put.assert_not_called()

    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.put")
    def test_applies_owner_display_name_map(self, mock_put):
        mock_put.return_value = mock.MagicMock(status_code=204)
        from requests.auth import HTTPBasicAuth

        issues = [{"key": "DEI-4", "summary": "domain.dag", "incident_owner": None}]
        dag_owner_map = {"domain.dag": "Data ForRent"}

        result = _resolve_issue_owners(issues, dag_owner_map, HTTPBasicAuth("u", "t"))

        assert result[0]["owner"] == "Data For Rent"


class TestGetScheduleTimeline:
    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.get")
    def test_calls_correct_url_and_returns_json(self, mock_get):
        mock_resp = mock.MagicMock()
        mock_resp.raise_for_status = mock.MagicMock()
        mock_resp.json.return_value = {"finalTimeline": {"rotations": []}}
        mock_get.return_value = mock_resp
        from requests.auth import HTTPBasicAuth

        result = _get_schedule_timeline(
            "cloud-123", HTTPBasicAuth("u", "t"), "2026-05-04"
        )

        assert result == {"finalTimeline": {"rotations": []}}
        called_url = mock_get.call_args[0][0]
        assert "cloud-123" in called_url
        assert JIRA_OPS_SCHEDULE_ID in called_url
        assert "2026-05-04T21:00:00Z" in called_url


class TestGetUserDisplay:
    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.get")
    def test_returns_display_name_and_email(self, mock_get):
        mock_resp = mock.MagicMock()
        mock_resp.raise_for_status = mock.MagicMock()
        mock_resp.json.return_value = {
            "displayName": "Zacarias Engineer",
            "emailAddress": "zacarias@example.com",
        }
        mock_get.return_value = mock_resp
        from requests.auth import HTTPBasicAuth

        result = _get_user_display("account-123", HTTPBasicAuth("u", "t"))

        assert result["displayName"] == "Zacarias Engineer"
        assert result["emailAddress"] == "zacarias@example.com"

    def test_returns_deleted_user_when_no_account_id(self):
        from requests.auth import HTTPBasicAuth

        result = _get_user_display("", HTTPBasicAuth("u", "t"))
        assert result["displayName"] == "Deleted User"

    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.get")
    def test_missing_email_address_falls_back_to_empty_string(self, mock_get):
        mock_resp = mock.MagicMock()
        mock_resp.raise_for_status = mock.MagicMock()
        mock_resp.json.return_value = {"displayName": "Zacarias Engineer"}
        mock_get.return_value = mock_resp
        from requests.auth import HTTPBasicAuth

        result = _get_user_display("account-123", HTTPBasicAuth("u", "t"))

        assert result["displayName"] == "Zacarias Engineer"
        assert result["emailAddress"] == ""


class TestGetOncallRecipients:
    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation._get_user_display"
    )
    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation._get_schedule_timeline"
    )
    def test_returns_recipient_for_normal_day(self, mock_schedule, mock_user_display):
        mock_schedule.return_value = {
            "finalTimeline": {
                "rotations": [
                    {
                        "name": "Primary",
                        "periods": [
                            {
                                "startDate": "2026-05-04T03:00:00Z",
                                "endDate": "2026-05-04T12:00:00Z",
                                "responder": {"id": "user-1"},
                            },
                            {
                                "startDate": "2026-05-05T00:00:00Z",
                                "endDate": "2026-05-05T03:00:00Z",
                                "responder": {"id": "user-2"},
                            },
                        ],
                    }
                ]
            }
        }
        mock_user_display.return_value = {
            "displayName": "Zacarias Engineer",
            "emailAddress": "zacarias@example.com",
        }
        from requests.auth import HTTPBasicAuth

        recipients, periods_length = _get_oncall_recipients(
            "cloud-id", HTTPBasicAuth("u", "t")
        )

        assert periods_length == 2
        assert len(recipients) == 1
        assert recipients[0]["emailAddress"] == "zacarias@example.com"

    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation._get_user_display"
    )
    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation._get_schedule_timeline"
    )
    def test_falls_back_on_exception_day(self, mock_schedule, mock_user_display):
        """Exception day: first fetch has 1 period; second re-fetch uses T00:00:00Z on D-1."""
        single_period_timeline = {
            "finalTimeline": {
                "rotations": [
                    {
                        "name": "Primary",
                        "periods": [
                            {
                                "startDate": "2026-05-04T12:00:00Z",
                                "endDate": "2026-05-04T24:00:00Z",
                                "responder": {"id": "user-1"},
                            }
                        ],
                    }
                ]
            }
        }
        mock_schedule.return_value = single_period_timeline
        mock_user_display.return_value = {
            "displayName": "Bob Engineer",
            "emailAddress": "bob@example.com",
        }
        from requests.auth import HTTPBasicAuth

        recipients, periods_length = _get_oncall_recipients(
            "cloud-id", HTTPBasicAuth("u", "t")
        )

        assert periods_length == 1
        assert mock_schedule.call_count == 2
        _, second_call_kwargs = mock_schedule.call_args_list[1]
        assert second_call_kwargs.get("time_suffix") == "T00:00:00Z", (
            "Exception path must re-fetch D-1 at midnight UTC (T00:00:00Z), "
            "not change shift_date to today"
        )
        assert len(recipients) == 1
        assert recipients[0]["emailAddress"] == "bob@example.com"


class TestCountVoiceWakeups:
    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.get")
    def test_returns_zero_when_no_alerts(self, mock_get):
        mock_resp = mock.MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {"values": []}
        mock_get.return_value = mock_resp
        from requests.auth import HTTPBasicAuth

        result = _count_voice_wakeups("cloud-id", HTTPBasicAuth("u", "t"), 2)
        assert result == 0

    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.get")
    def test_counts_voice_sent_log_entries(self, mock_get):
        alerts_resp = mock.MagicMock()
        alerts_resp.status_code = 200
        alerts_resp.json.return_value = {"values": [{"id": "alert-1"}]}

        logs_resp = mock.MagicMock()
        logs_resp.status_code = 200
        logs_resp.json.return_value = {
            "values": [
                {"log": "Notification sent [voice] -> Sent to zacarias@example.com"},
                {"log": "Notification sent [email] -> Sent to zacarias@example.com"},
            ]
        }

        mock_get.side_effect = [alerts_resp, logs_resp]
        from requests.auth import HTTPBasicAuth

        result = _count_voice_wakeups("cloud-id", HTTPBasicAuth("u", "t"), 2)
        assert result == 1

    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.get")
    def test_returns_zero_when_api_fails(self, mock_get):
        mock_resp = mock.MagicMock()
        mock_resp.status_code = 500
        mock_get.return_value = mock_resp
        from requests.auth import HTTPBasicAuth

        result = _count_voice_wakeups("cloud-id", HTTPBasicAuth("u", "t"), 2)
        assert result == 0

    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.get")
    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.datetime")
    def test_normal_day_window_starts_at_previous_day_21h(self, mock_dt, mock_get):
        """Normal shift starts D-1 21:00; window must not be truncated to midnight."""
        from datetime import datetime as real_datetime
        from zoneinfo import ZoneInfo

        sp_tz = ZoneInfo("America/Sao_Paulo")
        fixed_now = real_datetime(2026, 6, 9, 12, 0, 0, tzinfo=sp_tz)
        mock_dt.now.return_value = fixed_now
        mock_dt.side_effect = lambda *a, **kw: real_datetime(*a, **kw)

        mock_resp = mock.MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {"values": []}
        mock_get.return_value = mock_resp
        from requests.auth import HTTPBasicAuth

        _count_voice_wakeups("cloud-id", HTTPBasicAuth("u", "t"), 2)

        call_params = (
            mock_get.call_args_list[0][1].get("params") or mock_get.call_args_list[0][0]
        )
        expected_start = int(
            real_datetime(2026, 6, 8, 21, 0, 0, tzinfo=sp_tz).timestamp()
        )
        assert str(expected_start) in str(call_params), (
            f"Expected start timestamp {expected_start} (D-1 21:00) in query params, got {call_params}"
        )


class TestNotifyDagRotationCallable:
    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.post")
    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation._count_voice_wakeups"
    )
    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation._get_oncall_recipients"
    )
    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation._resolve_issue_owners"
    )
    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation._fetch_dei_issues"
    )
    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.Variable.get")
    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation.ConfigurationService"
    )
    def test_sends_notification_with_issues_and_wakeups(
        self,
        mock_cfg_cls,
        mock_var_get,
        mock_fetch,
        mock_resolve,
        mock_oncall,
        mock_wakeups,
        mock_post,
    ):
        mock_cfg_cls.return_value.get_config.return_value = _MOCK_WEBHOOK_KEYS
        mock_var_get.side_effect = lambda key, default_var=None: {
            "NOTIFICATION_HUB_DAG_ROTATION_WEBHOOK": "https://notification-hub.example.com/webhook",
            "SECRET_JIRA_API": _MOCK_JIRA_SECRET,
            "SECRET_JIRA_OPS_API": _MOCK_JIRA_OPS_SECRET,
        }.get(key, default_var)
        mock_fetch.return_value = [
            {"key": "DEI-1", "summary": "domain.dag", "incident_owner": "Data People"}
        ]
        mock_resolve.return_value = [
            {
                "key": "DEI-1",
                "summary": "domain.dag",
                "incident_owner": "Data People",
                "owner": "Data People",
            }
        ]
        mock_oncall.return_value = (
            [{"displayName": "Zacarias", "emailAddress": "zacarias@example.com"}],
            2,
        )
        mock_wakeups.return_value = 3

        mock_resp = mock.MagicMock()
        mock_resp.raise_for_status = mock.MagicMock()
        mock_post.return_value = mock_resp

        mock_session = mock.MagicMock()
        mock_session.query.return_value.filter.return_value.all.return_value = []

        notify_dag_rotation(session=mock_session)

        mock_post.assert_called_once()
        call_kwargs = mock_post.call_args[1]
        payload = call_kwargs["json"]
        assert payload["called_count"] == "3"
        assert len(payload["error_list"]) == 1
        assert payload["email"] == "zacarias@example.com"

    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation._get_oncall_recipients"
    )
    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation._resolve_issue_owners"
    )
    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation._fetch_dei_issues"
    )
    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.Variable.get")
    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation.ConfigurationService"
    )
    def test_skips_notification_when_no_recipients(
        self,
        mock_cfg_cls,
        mock_var_get,
        mock_fetch,
        mock_resolve,
        mock_oncall,
    ):
        mock_cfg_cls.return_value.get_config.return_value = _MOCK_WEBHOOK_KEYS
        mock_var_get.side_effect = lambda key, default_var=None: {
            "NOTIFICATION_HUB_DAG_ROTATION_WEBHOOK": "https://notification-hub.example.com/webhook",
            "SECRET_JIRA_API": _MOCK_JIRA_SECRET,
            "SECRET_JIRA_OPS_API": _MOCK_JIRA_OPS_SECRET,
        }.get(key, default_var)
        mock_fetch.return_value = []
        mock_resolve.return_value = []
        mock_oncall.return_value = ([], 2)

        mock_session = mock.MagicMock()
        mock_session.query.return_value.filter.return_value.all.return_value = []

        with mock.patch(
            "dags.governance.notify_dag_rotation.notify_dag_rotation.requests.post"
        ) as mock_post:
            notify_dag_rotation(session=mock_session)
            mock_post.assert_not_called()

    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation._count_voice_wakeups"
    )
    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation._get_oncall_recipients"
    )
    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation._resolve_issue_owners"
    )
    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation._fetch_dei_issues"
    )
    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.Variable.get")
    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation.ConfigurationService"
    )
    def test_skips_post_when_webhook_not_configured(
        self,
        mock_cfg_cls,
        mock_var_get,
        mock_fetch,
        mock_resolve,
        mock_oncall,
        mock_wakeups,
    ):
        mock_cfg_cls.return_value.get_config.return_value = _MOCK_WEBHOOK_KEYS
        mock_var_get.side_effect = lambda key, default_var=None: {
            "NOTIFICATION_HUB_DAG_ROTATION_WEBHOOK": None,
            "SECRET_JIRA_API": _MOCK_JIRA_SECRET,
            "SECRET_JIRA_OPS_API": _MOCK_JIRA_OPS_SECRET,
        }.get(key, default_var)
        mock_fetch.return_value = []
        mock_resolve.return_value = []
        mock_oncall.return_value = (
            [{"displayName": "Zacarias", "emailAddress": "zacarias@example.com"}],
            2,
        )
        mock_wakeups.return_value = 0

        mock_session = mock.MagicMock()
        mock_session.query.return_value.filter.return_value.all.return_value = []

        with mock.patch(
            "dags.governance.notify_dag_rotation.notify_dag_rotation.requests.post"
        ) as mock_post:
            notify_dag_rotation(session=mock_session)
            mock_post.assert_not_called()


class TestIsGchatWebhook:
    def test_returns_true_for_googleapis_url(self):
        assert _is_gchat_webhook(
            "https://chat.googleapis.com/v1/spaces/ABC/messages?key=x&token=y"
        )

    def test_returns_false_for_notification_hub_url(self):
        assert not _is_gchat_webhook(
            "https://notification-hub-internal-api.quintoandar.com.br/webhook/analytics-eng-oncall"
        )

    def test_returns_false_for_arbitrary_url(self):
        assert not _is_gchat_webhook("https://example.com/webhook")


class TestWrapForGchat:
    def _card_text(self, result: dict) -> str:
        card = result["cardsV2"][0]["card"]
        texts = []
        texts.append(card["header"]["title"])
        for section in card["sections"]:
            if section.get("header"):
                texts.append(section["header"])
            for widget in section["widgets"]:
                if "textParagraph" in widget:
                    texts.append(widget["textParagraph"]["text"])
        return "\n".join(texts)

    def test_produces_cardsv2_matching_prod_format(self):
        payload = {
            "email": "zacarias@example.com",
            "start_time": "2026-06-07T21:00",
            "called_count": "2",
            "error_list": [
                {
                    "url": "https://jira/DEI-1",
                    "key": "DEI-1",
                    "owner": "Data People",
                }
            ],
        }
        result = _wrap_for_gchat(payload)

        assert "cardsV2" in result
        full = self._card_text(result)
        assert "Bot do Platão Data Engineers" in full
        assert "Plantonista:" in full
        assert "zacarias@example.com" in full
        assert "Início:" in full
        assert "2026-06-07T21:00" in full
        assert "Acordamentos:" in full
        assert "2" in full
        alerts_widgets = result["cardsV2"][0]["card"]["sections"][1]["widgets"]
        assert any(
            "Tivemos 1 erros" in w["textParagraph"]["text"] for w in alerts_widgets
        )
        issue_widget = next(
            w for w in alerts_widgets if "DEI-1" in w["textParagraph"]["text"]
        )
        assert "Data People" in issue_widget["textParagraph"]["text"]
        assert len(alerts_widgets) == 2

    def test_card_has_two_sections_with_divider_widget(self):
        payload = {
            "email": "zacarias@example.com",
            "start_time": "2026-06-07T21:00",
            "called_count": "0",
            "error_list": [],
        }
        result = _wrap_for_gchat(payload)
        sections = result["cardsV2"][0]["card"]["sections"]
        assert len(sections) == 2
        assert sections[0]["widgets"][0]["textParagraph"]["text"]
        assert sections[1]["header"] == "Alertas"

    def test_shows_no_errors_when_empty_list(self):
        payload = {
            "email": "zacarias@example.com",
            "start_time": "2026-06-07T21:00",
            "called_count": "0",
            "error_list": [],
        }
        result = _wrap_for_gchat(payload)
        assert "Nenhum erro no período." in self._card_text(result)

    def test_handles_list_email(self):
        payload = {
            "email": ["a@example.com", "b@example.com"],
            "start_time": "2026-06-07T21:00",
            "called_count": "0",
            "error_list": [],
        }
        result = _wrap_for_gchat(payload)
        assert "['a@example.com', 'b@example.com']" in self._card_text(result)


class TestNotifyDagRotationDAG:
    def test_dag_identity_and_tasks(self):
        assert dag.dag_id == "governance.notify_dag_rotation"
        assert set(dag.task_ids) == {"notify_dag_rotation"}
        assert "monitoring" in dag.tags
        assert "oncall" in dag.tags
        assert "platform" in dag.tags

    def test_dag_schedule(self):
        assert dag.schedule_interval == "0 12 * * *"

    def test_dag_does_not_catchup(self):
        assert dag.catchup is False
