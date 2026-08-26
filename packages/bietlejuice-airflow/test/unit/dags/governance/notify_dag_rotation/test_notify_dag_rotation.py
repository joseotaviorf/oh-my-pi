"""Unit tests for platform notify_dag_rotation DAG logic and structure."""

from __future__ import annotations

import json
from unittest import mock

import pytest

from dags.governance.notify_dag_rotation.notify_dag_rotation import (
    _OWNER_DISPLAY_NAME_MAP,
    INCIDENT_OWNER_FIELD,
    JIRA_OPS_SCHEDULE_ID,
    SOURCE_AIRFLOW_ERROR,
    SOURCE_RUNTIME_ANOMALY,
    SOURCE_UNKNOWN,
    _alert_matches_issue,
    _classify_incident_source,
    _clean_dag_owner,
    _count_voice_wakeups,
    _display_owner_name,
    _enrich_issues_from_alerts,
    _environment_suffix,
    _extract_dag_from_alert,
    _fetch_classified_alerts,
    _fetch_dei_issues,
    _format_issue_alert_text,
    _get_oncall_recipients,
    _get_schedule_timeline,
    _get_user_display,
    _incident_owner_from_dag,
    _is_gchat_webhook,
    _parse_optional_datetime,
    _parse_rfc3339,
    _resolve_issue_owners,
    _should_include_oncall_period,
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

    def test_display_owner_falls_back_to_raw_enum_value(self):
        assert _display_owner_name("Data House and Listing") == "Data House and Listing"
        assert _display_owner_name("AE All") == "AE All"
        assert _display_owner_name("Search") == "MLOps"
        assert (
            _display_owner_name("Tech Platform Enterprise Engineering")
            == "Tech Platform Enterprise Engineering"
        )


class TestIncidentOwnerFromDag:
    def test_wonka_prefix_maps_to_mlops_even_without_airflow_owner(self):
        assert (
            _incident_owner_from_dag("quintoml.wonka.user_sale_houses_viewed", None)
            == "MLOps"
        )

    def test_wonka_search_owner_maps_to_mlops(self):
        assert (
            _incident_owner_from_dag("quintoml.wonka.user_sale_houses_viewed", "Search")
            == "MLOps"
        )

    def test_non_wonka_uses_airflow_owner(self):
        assert (
            _incident_owner_from_dag("bietlejuice.dw_listing", "Data House and Listing")
            == "Data House and Listing"
        )

    def test_non_wonka_missing_owner_is_ae_all(self):
        assert _incident_owner_from_dag("bietlejuice.unknown", None) == "AE All"


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
                        "customfield_31231": {"value": "Data People"},
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
        requested_fields = mock_post.call_args[1]["json"]["fields"]
        assert INCIDENT_OWNER_FIELD in requested_fields
        assert "customfield_12078" not in requested_fields

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
                        "customfield_31231": None,
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
                        "customfield_31231": None,
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
                        "customfield_31231": None,
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
        put_payload = mock_put.call_args[1]["json"]
        assert put_payload == {
            "fields": {INCIDENT_OWNER_FIELD: {"value": "Data People"}}
        }

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
        mock_put.assert_called_once()
        put_payload = mock_put.call_args[1]["json"]
        assert put_payload == {
            "fields": {INCIDENT_OWNER_FIELD: {"value": "Data ForRent"}}
        }

    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.put")
    def test_preserves_house_and_listing_already_set_on_31231(self, mock_put):
        from requests.auth import HTTPBasicAuth

        issues = [
            {
                "key": "DEI-26333",
                "summary": "bietlejuice.dw_listing",
                "incident_owner": "Data House and Listing",
            }
        ]
        result = _resolve_issue_owners(issues, {}, HTTPBasicAuth("u", "t"))

        assert result[0]["owner"] == "Data House and Listing"
        mock_put.assert_not_called()

    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.put")
    def test_house_and_listing_owner_is_written_to_31231(self, mock_put):
        """DEI-26333: DAG owner exists even if missing from the legacy display map."""
        mock_put.return_value = mock.MagicMock(status_code=204)
        from requests.auth import HTTPBasicAuth

        issues = [
            {
                "key": "DEI-26333",
                "summary": "bietlejuice.dw_listing",
                "incident_owner": None,
            }
        ]
        dag_owner_map = {"bietlejuice.dw_listing": "Data House and Listing"}

        result = _resolve_issue_owners(issues, dag_owner_map, HTTPBasicAuth("u", "t"))

        assert result[0]["owner"] == "Data House and Listing"
        mock_put.assert_called_once()
        put_payload = mock_put.call_args[1]["json"]
        assert put_payload == {
            "fields": {INCIDENT_OWNER_FIELD: {"value": "Data House and Listing"}}
        }

    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.put")
    def test_wonka_search_dag_is_written_as_mlops(self, mock_put):
        """DEI-26370: Search-owned Wonka DAGs land on MLOps in customfield_31231."""
        mock_put.return_value = mock.MagicMock(status_code=204)
        from requests.auth import HTTPBasicAuth

        issues = [
            {
                "key": "DEI-26370",
                "summary": "quintoml.wonka.user_sale_houses_viewed",
                "incident_owner": None,
            }
        ]
        dag_owner_map = {"quintoml.wonka.user_sale_houses_viewed": "Search"}

        result = _resolve_issue_owners(issues, dag_owner_map, HTTPBasicAuth("u", "t"))

        assert result[0]["owner"] == "MLOps"
        mock_put.assert_called_once()
        put_payload = mock_put.call_args[1]["json"]
        assert put_payload == {"fields": {INCIDENT_OWNER_FIELD: {"value": "MLOps"}}}

    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.put")
    def test_wonka_prefix_maps_to_mlops_when_dag_missing_from_airflow(self, mock_put):
        mock_put.return_value = mock.MagicMock(status_code=204)
        from requests.auth import HTTPBasicAuth

        issues = [
            {
                "key": "DEI-26370",
                "summary": "quintoml.wonka.user_sale_houses_viewed",
                "incident_owner": None,
            }
        ]
        result = _resolve_issue_owners(issues, {}, HTTPBasicAuth("u", "t"))

        assert result[0]["owner"] == "MLOps"
        put_payload = mock_put.call_args[1]["json"]
        assert put_payload == {"fields": {INCIDENT_OWNER_FIELD: {"value": "MLOps"}}}


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
        from datetime import datetime
        from zoneinfo import ZoneInfo

        from requests.auth import HTTPBasicAuth

        sp_tz = ZoneInfo("America/Sao_Paulo")
        monday_anchor = datetime(2026, 5, 5, 9, 0, 0, tzinfo=sp_tz)

        recipients, periods_length = _get_oncall_recipients(
            "cloud-id", HTTPBasicAuth("u", "t"), now_sp=monday_anchor
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
        from datetime import datetime
        from zoneinfo import ZoneInfo

        from requests.auth import HTTPBasicAuth

        sp_tz = ZoneInfo("America/Sao_Paulo")
        monday_anchor = datetime(2026, 5, 5, 9, 0, 0, tzinfo=sp_tz)

        recipients, periods_length = _get_oncall_recipients(
            "cloud-id", HTTPBasicAuth("u", "t"), now_sp=monday_anchor
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

    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation._get_user_display"
    )
    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation._get_schedule_timeline"
    )
    def test_sunday_morning_fetches_exceptional_shift_on_today(
        self, mock_schedule, mock_user_display
    ):
        """Sunday 09:00: timeline starts at 09:00 BRT (T12:00:00Z) to get the short shift."""
        from datetime import datetime
        from zoneinfo import ZoneInfo

        from requests.auth import HTTPBasicAuth

        sp_tz = ZoneInfo("America/Sao_Paulo")
        sunday_anchor = datetime(2026, 7, 26, 9, 0, 0, tzinfo=sp_tz)
        mock_schedule.return_value = {
            "finalTimeline": {
                "rotations": [
                    {
                        "name": "Primary",
                        "periods": [
                            {
                                "startDate": "2026-07-26T12:00:00Z",
                                "endDate": "2026-07-26T15:00:00Z",
                                "type": "override",
                                "responder": {"id": "user-1"},
                            }
                        ],
                    }
                ]
            }
        }
        mock_user_display.return_value = {
            "displayName": "Weekend Engineer",
            "emailAddress": "weekend@example.com",
        }

        recipients, periods_length = _get_oncall_recipients(
            "cloud-id", HTTPBasicAuth("u", "t"), now_sp=sunday_anchor
        )

        assert periods_length == 1
        assert mock_schedule.call_count == 1
        call_args, call_kwargs = mock_schedule.call_args
        assert call_args[2] == "2026-07-26"
        assert call_kwargs.get("time_suffix") == "T12:00:00Z"
        assert len(recipients) == 1
        assert recipients[0]["emailAddress"] == "weekend@example.com"

    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation._get_user_display"
    )
    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation._get_schedule_timeline"
    )
    def test_sunday_morning_prefers_0900_over_midnight_primary(
        self, mock_schedule, mock_user_display
    ):
        """Prod 2026-08-16: Guilherme 09:00-12:00 must win over Isadora hour=0 Primary."""
        from datetime import datetime
        from zoneinfo import ZoneInfo

        from requests.auth import HTTPBasicAuth

        sp_tz = ZoneInfo("America/Sao_Paulo")
        sunday_anchor = datetime(2026, 8, 16, 9, 0, 0, tzinfo=sp_tz)

        def schedule_side_effect(*args, **kwargs):
            suffix = kwargs.get("time_suffix")
            if suffix == "T12:00:00Z":
                return {
                    "finalTimeline": {
                        "rotations": [
                            {
                                "name": "Primary",
                                "periods": [
                                    {
                                        # 09:00-12:00 BRT — Guilherme (correct Sunday plantonista)
                                        "startDate": "2026-08-16T12:00:00Z",
                                        "endDate": "2026-08-16T15:00:00Z",
                                        "type": "override",
                                        "responder": {"id": "user-guilherme"},
                                    }
                                ],
                            }
                        ]
                    }
                }
            # Midnight window only sees the earlier Primary (what prod logged).
            return {
                "finalTimeline": {
                    "rotations": [
                        {
                            "name": "Primary",
                            "periods": [
                                {
                                    "startDate": "2026-08-16T03:00:00Z",
                                    "endDate": "2026-08-16T15:00:00Z",
                                    "type": "historical",
                                    "responder": {"id": "user-isadora"},
                                }
                            ],
                        }
                    ]
                }
            }

        mock_schedule.side_effect = schedule_side_effect
        mock_user_display.side_effect = lambda account_id, _auth: {
            "user-guilherme": {
                "displayName": "GUILHERME DOMINGOS SACRAMENTO",
                "emailAddress": "guilherme@example.com",
            },
            "user-isadora": {
                "displayName": "Isadora Eliziario Gallerani",
                "emailAddress": "isadora@example.com",
            },
        }.get(account_id, {"displayName": account_id, "emailAddress": ""})

        recipients, periods_length = _get_oncall_recipients(
            "cloud-id", HTTPBasicAuth("u", "t"), now_sp=sunday_anchor
        )

        assert periods_length == 1
        assert mock_schedule.call_count == 1
        assert mock_schedule.call_args.kwargs.get("time_suffix") == "T12:00:00Z"
        assert len(recipients) == 1
        assert recipients[0]["emailAddress"] == "guilherme@example.com"

    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation._get_user_display"
    )
    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation._get_schedule_timeline"
    )
    def test_sunday_morning_retries_midnight_window_if_needed(
        self, mock_schedule, mock_user_display
    ):
        """If T12:00:00Z has no hour=9 period, fall back to T00:00:00Z still requiring hour=9."""
        from datetime import datetime
        from zoneinfo import ZoneInfo

        from requests.auth import HTTPBasicAuth

        sp_tz = ZoneInfo("America/Sao_Paulo")
        sunday_anchor = datetime(2026, 8, 16, 9, 0, 0, tzinfo=sp_tz)

        def schedule_side_effect(*args, **kwargs):
            suffix = kwargs.get("time_suffix")
            if suffix == "T12:00:00Z":
                return {
                    "finalTimeline": {"rotations": [{"name": "Primary", "periods": []}]}
                }
            return {
                "finalTimeline": {
                    "rotations": [
                        {
                            "name": "Primary",
                            "periods": [
                                {
                                    "startDate": "2026-08-16T03:00:00Z",
                                    "endDate": "2026-08-16T12:00:00Z",
                                    "responder": {"id": "user-isadora"},
                                },
                                {
                                    "startDate": "2026-08-16T12:00:00Z",
                                    "endDate": "2026-08-16T15:00:00Z",
                                    "responder": {"id": "user-guilherme"},
                                },
                            ],
                        }
                    ]
                }
            }

        mock_schedule.side_effect = schedule_side_effect
        mock_user_display.side_effect = lambda account_id, _auth: {
            "user-guilherme": {
                "displayName": "GUILHERME DOMINGOS SACRAMENTO",
                "emailAddress": "guilherme@example.com",
            },
            "user-isadora": {
                "displayName": "Isadora Eliziario Gallerani",
                "emailAddress": "isadora@example.com",
            },
        }.get(account_id, {"displayName": account_id, "emailAddress": ""})

        recipients, periods_length = _get_oncall_recipients(
            "cloud-id", HTTPBasicAuth("u", "t"), now_sp=sunday_anchor
        )

        assert periods_length == 1
        assert mock_schedule.call_count == 2
        assert mock_schedule.call_args_list[0].kwargs.get("time_suffix") == "T12:00:00Z"
        assert mock_schedule.call_args_list[1].kwargs.get("time_suffix") == "T00:00:00Z"
        assert len(recipients) == 1
        assert recipients[0]["emailAddress"] == "guilherme@example.com"


class TestShouldIncludeOncallPeriod:
    def test_sunday_and_holiday_require_hour_9(self):
        from datetime import datetime
        from zoneinfo import ZoneInfo

        sp_tz = ZoneInfo("America/Sao_Paulo")
        assert _should_include_oncall_period(
            datetime(2026, 8, 16, 9, 0, tzinfo=sp_tz),
            periods_length_exception=1,
            sunday_morning=True,
        )
        assert not _should_include_oncall_period(
            datetime(2026, 8, 16, 0, 0, tzinfo=sp_tz),
            periods_length_exception=1,
            sunday_morning=True,
        )
        assert _should_include_oncall_period(
            datetime(2026, 5, 4, 9, 0, tzinfo=sp_tz),
            periods_length_exception=1,
            sunday_morning=False,
        )
        assert not _should_include_oncall_period(
            datetime(2026, 5, 4, 0, 0, tzinfo=sp_tz),
            periods_length_exception=1,
            sunday_morning=False,
        )

    def test_normal_day_requires_hour_21(self):
        from datetime import datetime
        from zoneinfo import ZoneInfo

        sp_tz = ZoneInfo("America/Sao_Paulo")
        assert _should_include_oncall_period(
            datetime(2026, 5, 4, 21, 0, tzinfo=sp_tz),
            periods_length_exception=2,
            sunday_morning=False,
        )
        assert not _should_include_oncall_period(
            datetime(2026, 5, 4, 9, 0, tzinfo=sp_tz),
            periods_length_exception=2,
            sunday_morning=False,
        )


class TestExtractDagFromAlert:
    def test_matches_known_dag_id_in_message(self):
        result = _extract_dag_from_alert(
            "domain.dag failed on task X", {"domain.dag", "other.dag"}
        )
        assert result == "domain.dag"

    def test_prefers_longest_match(self):
        result = _extract_dag_from_alert(
            "domain.sub.dag is late", {"domain.sub", "domain.sub.dag"}
        )
        assert result == "domain.sub.dag"

    def test_falls_back_to_message_when_no_known_match(self):
        result = _extract_dag_from_alert("some free-text alert", {"domain.dag"})
        assert result == "some free-text alert"

    def test_falls_back_to_message_when_no_known_ids(self):
        assert _extract_dag_from_alert("raw message", None) == "raw message"

    def test_placeholder_when_message_empty(self):
        assert _extract_dag_from_alert("", {"domain.dag"}) == "Alerta sem descrição"

    def test_matches_known_dag_id_in_alias(self):
        result = _extract_dag_from_alert(
            "DAG runtime anomaly",
            {"bietlejuice.dw_listing"},
            extra_texts=["dag-runtime-bietlejuice.dw_listing-run1"],
        )
        assert result == "bietlejuice.dw_listing"


class TestClassifyIncidentSource:
    def test_rubinho_alias_is_runtime_anomaly(self):
        assert (
            _classify_incident_source(
                "anything",
                alias="dag-runtime-bietlejuice.dw_listing-scheduled__1",
            )
            == SOURCE_RUNTIME_ANOMALY
        )

    def test_runtime_anomaly_in_message(self):
        assert (
            _classify_incident_source("DAG runtime anomaly: bietlejuice.dw_listing")
            == SOURCE_RUNTIME_ANOMALY
        )

    def test_runtime_anomaly_in_tags(self):
        assert (
            _classify_incident_source(
                "slow dag",
                tags=["bietlejuice.dw_listing", "runtime anomaly", "critical"],
            )
            == SOURCE_RUNTIME_ANOMALY
        )

    def test_airflow_task_failure_message(self):
        assert (
            _classify_incident_source("DAG: domain.dag - Task: execute-job-cluster")
            == SOURCE_AIRFLOW_ERROR
        )

    def test_airflow_dag_failure_message(self):
        assert (
            _classify_incident_source("DAG: domain.dag Failed") == SOURCE_AIRFLOW_ERROR
        )

    def test_airflow_tags(self):
        assert (
            _classify_incident_source(
                "domain.dag",
                tags=["domain.dag", "execute-job-cluster", "task failed"],
            )
            == SOURCE_AIRFLOW_ERROR
        )

    def test_unknown_when_no_signal(self):
        assert _classify_incident_source("manual page") == SOURCE_UNKNOWN


class TestParseOptionalDatetime:
    def test_parses_rfc3339(self):
        result = _parse_optional_datetime("2026-05-05T01:00:00Z")
        assert result is not None
        assert result.year == 2026

    def test_parses_epoch_milliseconds(self):
        result = _parse_optional_datetime(1746406800000)
        assert result is not None

    def test_none_and_empty(self):
        assert _parse_optional_datetime(None) is None
        assert _parse_optional_datetime("") is None


class TestEnrichIssuesFromAlerts:
    def test_matches_closest_alert_and_does_not_reuse(self):
        issues = [
            {
                "key": "DEI-1",
                "summary": "domain.dag",
                "created": "2026-05-05T01:00:00Z",
            },
            {
                "key": "DEI-2",
                "summary": "domain.dag",
                "created": "2026-05-05T01:20:00Z",
            },
        ]
        alerts = [
            {
                "alert_id": "a1",
                "dag": "domain.dag",
                "message": "DAG: domain.dag - Task: t1",
                "created_at": "2026-05-05T01:01:00Z",
                "source_label": SOURCE_AIRFLOW_ERROR,
                "had_voice": True,
            },
            {
                "alert_id": "a2",
                "dag": "domain.dag",
                "message": "DAG runtime anomaly: domain.dag",
                "created_at": "2026-05-05T01:19:00Z",
                "source_label": SOURCE_RUNTIME_ANOMALY,
                "had_voice": False,
            },
        ]

        result = _enrich_issues_from_alerts(issues, alerts)

        assert result[0]["source_label"] == SOURCE_AIRFLOW_ERROR
        assert result[0]["had_voice"] is True
        assert result[0]["dag"] == "domain.dag"
        assert result[1]["source_label"] == SOURCE_RUNTIME_ANOMALY
        assert result[1]["had_voice"] is False
        assert result[1]["dag"] == "domain.dag"

    def test_unmatched_issue_is_unknown_without_voice(self):
        issues = [
            {
                "key": "DEI-9",
                "summary": "manual.card",
                "created": "2026-05-05T01:00:00Z",
            }
        ]
        result = _enrich_issues_from_alerts(issues, [])
        assert result[0]["source_label"] == SOURCE_UNKNOWN
        assert result[0]["had_voice"] is False
        assert result[0]["dag"] == "manual.card"

    def test_matches_dag_id_inside_alert_message(self):
        issues = [{"key": "DEI-3", "summary": "bietlejuice.dw_listing"}]
        alerts = [
            {
                "alert_id": "a1",
                "dag": "DAG runtime anomaly: bietlejuice.dw_listing",
                "message": "DAG runtime anomaly: bietlejuice.dw_listing",
                "source_label": SOURCE_RUNTIME_ANOMALY,
                "had_voice": False,
            }
        ]
        result = _enrich_issues_from_alerts(issues, alerts)
        assert result[0]["source_label"] == SOURCE_RUNTIME_ANOMALY
        assert result[0]["had_voice"] is False
        assert result[0]["dag"] == "bietlejuice.dw_listing"

    def test_does_not_match_shorter_dag_id_inside_longer_dag(self):
        issues = [{"key": "DEI-1", "summary": "bietlejuice.dw_listing"}]
        alerts = [
            {
                "alert_id": "a1",
                "dag": "bietlejuice.dw_listing_owners",
                "message": "DAG: bietlejuice.dw_listing_owners - Task: t1",
                "source_label": SOURCE_AIRFLOW_ERROR,
                "had_voice": True,
            }
        ]
        result = _enrich_issues_from_alerts(issues, alerts)
        assert result[0]["source_label"] == SOURCE_UNKNOWN
        assert result[0]["had_voice"] is False
        assert result[0]["dag"] == "bietlejuice.dw_listing"

    def test_matches_dag_id_in_rubinho_alias(self):
        assert _alert_matches_issue(
            {
                "dag": "Alerta sem descrição",
                "message": "DAG runtime anomaly",
                "alias": "dag-runtime-bietlejuice.dw_listing-scheduled__1",
                "tags": [],
            },
            "bietlejuice.dw_listing",
        )

    def test_pairs_earlier_card_first_even_when_listed_later(self):
        issues = [
            {
                "key": "DEI-2",
                "summary": "domain.dag",
                "created": "2026-05-05T01:02:00Z",
            },
            {
                "key": "DEI-1",
                "summary": "domain.dag",
                "created": "2026-05-05T01:00:00Z",
            },
        ]
        alerts = [
            {
                "alert_id": "a1",
                "dag": "domain.dag",
                "created_at": "2026-05-05T01:01:00Z",
                "source_label": SOURCE_AIRFLOW_ERROR,
                "had_voice": True,
            },
            {
                "alert_id": "a2",
                "dag": "domain.dag",
                "created_at": "2026-05-05T01:03:00Z",
                "source_label": SOURCE_RUNTIME_ANOMALY,
                "had_voice": False,
            },
        ]

        result = _enrich_issues_from_alerts(issues, alerts)

        by_key = {issue["key"]: issue for issue in result}
        assert result[0]["key"] == "DEI-2"
        assert by_key["DEI-1"]["source_label"] == SOURCE_AIRFLOW_ERROR
        assert by_key["DEI-1"]["had_voice"] is True
        assert by_key["DEI-2"]["source_label"] == SOURCE_RUNTIME_ANOMALY
        assert by_key["DEI-2"]["had_voice"] is False


class TestCountVoiceWakeups:
    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.get")
    def test_returns_zero_when_no_alerts(self, mock_get):
        mock_resp = mock.MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {"values": []}
        mock_get.return_value = mock_resp
        from requests.auth import HTTPBasicAuth

        result = _count_voice_wakeups("cloud-id", HTTPBasicAuth("u", "t"), 2)
        assert result == []

    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.get")
    def test_counts_voice_sent_log_entries(self, mock_get):
        alerts_resp = mock.MagicMock()
        alerts_resp.status_code = 200
        alerts_resp.json.return_value = {
            "values": [{"id": "alert-1", "message": "domain.dag failed at task X"}]
        }

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

        result = _count_voice_wakeups(
            "cloud-id", HTTPBasicAuth("u", "t"), 2, known_dag_ids={"domain.dag"}
        )
        assert len(result) == 1
        assert result[0]["alert_id"] == "alert-1"
        assert result[0]["dag"] == "domain.dag"
        assert result[0]["had_voice"] is True

    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.get")
    def test_keeps_alerts_without_voice_in_classified_list(self, mock_get):
        alerts_resp = mock.MagicMock()
        alerts_resp.status_code = 200
        alerts_resp.json.return_value = {
            "values": [
                {
                    "id": "alert-1",
                    "message": "DAG runtime anomaly: domain.dag",
                    "tags": ["domain.dag", "runtime anomaly"],
                    "alias": "dag-runtime-domain.dag-r1",
                    "createdAt": "2026-05-05T01:00:00Z",
                },
                {
                    "id": "alert-2",
                    "message": "DAG: other.dag - Task: execute-job-cluster",
                    "tags": ["other.dag", "task failed"],
                    "createdAt": "2026-05-05T01:10:00Z",
                },
            ]
        }
        voice_logs = mock.MagicMock()
        voice_logs.status_code = 200
        voice_logs.json.return_value = {
            "values": [
                {"log": "Notification sent [voice] -> Sent to zacarias@example.com"}
            ]
        }
        silent_logs = mock.MagicMock()
        silent_logs.status_code = 200
        silent_logs.json.return_value = {
            "values": [
                {"log": "Notification sent [email] -> Sent to zacarias@example.com"}
            ]
        }
        mock_get.side_effect = [alerts_resp, voice_logs, silent_logs]
        from requests.auth import HTTPBasicAuth

        classified = _fetch_classified_alerts(
            "cloud-id",
            HTTPBasicAuth("u", "t"),
            2,
            known_dag_ids={"domain.dag", "other.dag"},
        )
        assert len(classified) == 2
        by_id = {item["alert_id"]: item for item in classified}
        assert by_id["alert-1"]["source_label"] == SOURCE_RUNTIME_ANOMALY
        assert by_id["alert-1"]["had_voice"] is True
        assert by_id["alert-1"]["dag"] == "domain.dag"
        assert by_id["alert-2"]["source_label"] == SOURCE_AIRFLOW_ERROR
        assert by_id["alert-2"]["had_voice"] is False
        wakeups = [item for item in classified if item["had_voice"]]
        assert [item["alert_id"] for item in wakeups] == ["alert-1"]

    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.get")
    def test_returns_empty_when_api_fails(self, mock_get):
        mock_resp = mock.MagicMock()
        mock_resp.status_code = 500
        mock_get.return_value = mock_resp
        from requests.auth import HTTPBasicAuth

        result = _count_voice_wakeups("cloud-id", HTTPBasicAuth("u", "t"), 2)
        assert result == []

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

    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.get")
    def test_sunday_voice_wakeup_window_covers_overnight_gap(self, mock_get):
        """Sunday report still counts alerts from Sat 21:00 → Sun 09:00 (no on-call overnight)."""
        from datetime import datetime
        from zoneinfo import ZoneInfo

        sp_tz = ZoneInfo("America/Sao_Paulo")
        sunday_anchor = datetime(2026, 7, 26, 9, 0, 0, tzinfo=sp_tz)

        mock_resp = mock.MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {"values": []}
        mock_get.return_value = mock_resp
        from requests.auth import HTTPBasicAuth

        _count_voice_wakeups(
            "cloud-id", HTTPBasicAuth("u", "t"), 1, now_sp=sunday_anchor
        )

        call_params = (
            mock_get.call_args_list[0][1].get("params") or mock_get.call_args_list[0][0]
        )
        expected_start = int(datetime(2026, 7, 25, 21, 0, 0, tzinfo=sp_tz).timestamp())
        assert str(expected_start) in str(call_params), (
            f"Expected start timestamp {expected_start} (Sat 21:00) in query params, "
            f"got {call_params}"
        )


class TestNotifyDagRotationCallable:
    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.post")
    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation._fetch_classified_alerts"
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
        mock_wakeups.return_value = [
            {
                "alert_id": "a1",
                "message": "DAG: domain.dag - Task: t1",
                "dag": "domain.dag",
                "source_label": SOURCE_AIRFLOW_ERROR,
                "had_voice": True,
            },
            {
                "alert_id": "a2",
                "message": "DAG: other.dag - Task: t1",
                "dag": "other.dag",
                "source_label": SOURCE_AIRFLOW_ERROR,
                "had_voice": True,
            },
            {
                "alert_id": "a3",
                "message": "DAG runtime anomaly: domain.dag",
                "dag": "domain.dag",
                "source_label": SOURCE_RUNTIME_ANOMALY,
                "had_voice": True,
            },
        ]

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
        # Deduplicated, first-seen order preserved.
        assert payload["wakeup_dags"] == ["domain.dag", "other.dag"]
        assert len(payload["error_list"]) == 1
        assert payload["error_list"][0]["source_label"] == SOURCE_AIRFLOW_ERROR
        assert payload["error_list"][0]["had_voice"] is True
        assert payload["error_list"][0]["dag"] == "domain.dag"
        assert payload["email"] == "zacarias@example.com"

    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.post")
    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation._fetch_classified_alerts"
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
    def test_webhook_token_goes_only_to_dag_rotation_route(
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
            "NOTIFICATION_HUB_DAG_ROTATION_WEBHOOK": "https://notification-hub.example.com/webhook/analytics-eng-oncall",
            "NOTIFICATION_HUB_IAM_ALERTS_WEBHOOK": "https://notification-hub.example.com/webhook/iam-alerts",
            "SECRET_NOTIFICATION_HUB_DAG_ROTATION_TOKEN": "token-under-test",
            "SECRET_JIRA_API": _MOCK_JIRA_SECRET,
            "SECRET_JIRA_OPS_API": _MOCK_JIRA_OPS_SECRET,
        }.get(key, default_var)
        cyber_issue = {
            "key": "DEI-9",
            "summary": "domain.dag",
            "incident_owner": "Tech Platform Cyber Security",
            "owner": "Tech Platform Cyber Security",
        }
        mock_fetch.return_value = [cyber_issue]
        mock_resolve.return_value = [cyber_issue]
        mock_oncall.return_value = (
            [{"displayName": "Zacarias", "emailAddress": "zacarias@example.com"}],
            2,
        )
        mock_wakeups.return_value = []

        mock_resp = mock.MagicMock()
        mock_resp.raise_for_status = mock.MagicMock()
        mock_post.return_value = mock_resp

        mock_session = mock.MagicMock()
        mock_session.query.return_value.filter.return_value.all.return_value = []

        notify_dag_rotation(session=mock_session)

        assert mock_post.call_count == 2, (
            "Expected a DAG_Rotation POST and an iam-alerts POST, "
            f"got {mock_post.call_count}"
        )
        dag_rotation_headers = mock_post.call_args_list[0][1]["headers"]
        iam_alerts_headers = mock_post.call_args_list[1][1]["headers"]
        assert dag_rotation_headers["X-Webhook-Token"] == "token-under-test"
        assert "X-Webhook-Token" not in iam_alerts_headers, (
            "The DAG_Rotation token must not leak into the iam-alerts POST"
        )

    @mock.patch("dags.governance.notify_dag_rotation.notify_dag_rotation.requests.post")
    @mock.patch(
        "dags.governance.notify_dag_rotation.notify_dag_rotation._fetch_classified_alerts"
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
    def test_posts_without_token_header_when_variable_unset(
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
            "NOTIFICATION_HUB_DAG_ROTATION_WEBHOOK": "https://notification-hub.example.com/webhook/analytics-eng-oncall",
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
        mock_wakeups.return_value = []

        mock_resp = mock.MagicMock()
        mock_resp.raise_for_status = mock.MagicMock()
        mock_post.return_value = mock_resp

        mock_session = mock.MagicMock()
        mock_session.query.return_value.filter.return_value.all.return_value = []

        notify_dag_rotation(session=mock_session)

        mock_post.assert_called_once()
        headers = mock_post.call_args[1]["headers"]
        assert "X-Webhook-Token" not in headers
        assert headers["Content-type"] == "application/json"

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
        "dags.governance.notify_dag_rotation.notify_dag_rotation._fetch_classified_alerts"
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
        mock_wakeups.return_value = []

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

    def test_annotates_source_and_acordamento_on_issue_lines(self):
        payload = {
            "email": "zacarias@example.com",
            "start_time": "2026-06-07T21:00",
            "called_count": "1",
            "error_list": [
                {
                    "url": "https://jira/DEI-26333",
                    "key": "DEI-26333",
                    "owner": "Data House and Listing",
                    "dag": "bietlejuice.dw_supply",
                    "source_label": SOURCE_RUNTIME_ANOMALY,
                    "had_voice": True,
                },
                {
                    "url": "https://jira/DEI-26334",
                    "key": "DEI-26334",
                    "owner": "QCX",
                    "dag": "other.dag",
                    "source_label": SOURCE_AIRFLOW_ERROR,
                    "had_voice": False,
                },
            ],
        }
        result = _wrap_for_gchat(payload)
        alerts_widgets = result["cardsV2"][0]["card"]["sections"][1]["widgets"]
        assert (
            "Tivemos 2 erros (1 com chamada):"
            in alerts_widgets[0]["textParagraph"]["text"]
        )
        listing_line = alerts_widgets[1]["textParagraph"]["text"]
        qcx_line = alerts_widgets[2]["textParagraph"]["text"]
        assert "DEI-26333" in listing_line
        assert "Data House and Listing" in listing_line
        assert "bietlejuice.dw_supply" in listing_line
        assert "Runtime anomaly" in listing_line
        assert "<b>Acordamento</b>" in listing_line
        assert "DEI-26334" in qcx_line
        assert "QCX" in qcx_line
        assert "other.dag" in qcx_line
        assert "Airflow error" in qcx_line
        assert "Acordamento" not in qcx_line

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

    def test_lists_wakeup_dags_under_acordamentos(self):
        payload = {
            "email": "zacarias@example.com",
            "start_time": "2026-06-07T21:00",
            "called_count": "2",
            "wakeup_dags": ["domain.dag", "other.dag"],
            "error_list": [],
        }
        result = _wrap_for_gchat(payload)
        summary = result["cardsV2"][0]["card"]["sections"][0]["widgets"][0][
            "textParagraph"
        ]["text"]
        assert "Acordamentos:" in summary
        assert "domain.dag" not in summary
        assert "other.dag" not in summary
        assert "•" not in summary

    def test_no_dag_bullets_when_wakeup_dags_absent(self):
        payload = {
            "email": "zacarias@example.com",
            "start_time": "2026-06-07T21:00",
            "called_count": "0",
            "error_list": [],
        }
        result = _wrap_for_gchat(payload)
        summary = result["cardsV2"][0]["card"]["sections"][0]["widgets"][0][
            "textParagraph"
        ]["text"]
        assert "•" not in summary

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


class TestFormatIssueAlertText:
    def test_includes_source_and_acordamento(self):
        text = _format_issue_alert_text(
            {
                "url": "https://jira/DEI-1",
                "key": "DEI-1",
                "owner": "QCX",
                "dag": "bietlejuice.dw_supply",
                "source_label": SOURCE_AIRFLOW_ERROR,
                "had_voice": True,
            }
        )
        assert text == (
            '<a href="https://jira/DEI-1">DEI-1</a> - QCX - bietlejuice.dw_supply'
            " - Airflow error - <b>Acordamento</b>"
        )

    def test_omits_acordamento_when_no_voice(self):
        text = _format_issue_alert_text(
            {
                "url": "https://jira/DEI-2",
                "key": "DEI-2",
                "owner": "QCX",
                "source_label": SOURCE_RUNTIME_ANOMALY,
                "had_voice": False,
            }
        )
        assert "Acordamento" not in text
        assert "Runtime anomaly" in text

    def test_omits_dag_when_empty(self):
        text = _format_issue_alert_text(
            {
                "url": "https://jira/DEI-3",
                "key": "DEI-3",
                "owner": "QCX",
                "source_label": SOURCE_UNKNOWN,
                "had_voice": False,
            }
        )
        assert text == ('<a href="https://jira/DEI-3">DEI-3</a> - QCX - Unknown')


class TestNotifyDagRotationDAG:
    def test_dag_identity_and_tasks(self):
        assert dag.dag_id == "governance.notify_dag_rotation"
        assert set(dag.task_ids) == {"notify_dag_rotation"}
        assert "monitoring" in dag.tags
        assert "oncall" in dag.tags
        assert "platform" in dag.tags

    def test_dag_schedule(self):
        assert dag.schedule_interval == "0 9 * * *"

    def test_dag_does_not_catchup(self):
        assert dag.catchup is False
