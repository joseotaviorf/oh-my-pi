"""Tests for DataHub catalog fallback in golden-query validation."""

from __future__ import annotations

from pathlib import Path
from typing import Callable

import yaml
from datahub_table_fallback import (
    DataHubFallbackSchemaClient,
    DataHubSchemaProbe,
    build_datahub_fallback_client,
)
from golden_query_metadata_validator import (
    MetadataSchemaClient,
    build_metadata_column_index,
)
from golden_query_schema_validator import validate_golden_query_sql

_SANDBOX_URN = "urn:li:dataset:(urn:li:dataPlatform:trino,hive.sandbox.nps_fr,PROD)"


def _fake_post_factory(
    *,
    existing_urns: set[str],
    schema_by_urn: dict[str, list[str]],
) -> Callable[..., tuple[dict, str]]:
    def _post(
        _url: str,
        _token: str | None,
        query: str,
        variables: dict,
        _timeout: float = 60.0,
    ):
        urn = variables.get("urn", "")
        if "entityExists" in query:
            return ({"entityExists": urn in existing_urns}, "ok")
        if "schemaMetadata" in query:
            fields = schema_by_urn.get(urn, [])
            return (
                {
                    "dataset": {
                        "schemaMetadata": {
                            "fields": [{"fieldPath": col} for col in fields]
                        }
                    }
                },
                "ok",
            )
        return ({}, "ok")

    return _post


def test_datahub_probe_resolves_sandbox_table():
    probe = DataHubSchemaProbe(
        post=_fake_post_factory(
            existing_urns={_SANDBOX_URN},
            schema_by_urn={_SANDBOX_URN: ["sk_nps_answer", "ts_answered"]},
        ),
        token="token",
    )
    assert probe.resolve_dataset_urn("sandbox", "nps_fr") == _SANDBOX_URN
    assert probe.column_names_for_table("sandbox", "nps_fr") == {
        "sk_nps_answer",
        "ts_answered",
    }


def test_fallback_client_uses_datahub_when_metadata_missing(tmp_path: Path):
    meta_dir = tmp_path / "dags" / "rent" / "dw_visit" / "metadata" / "dw"
    meta_dir.mkdir(parents=True)
    (meta_dir / "fact_visits.yml").write_text(
        yaml.safe_dump(
            {
                "database_name": "dw_visit",
                "table_name": "fact_visits",
                "description": "Visit fact for fallback tests.",
                "domain": "For Rent",
                "owner": "owner@quintoandar.com.br",
                "columns": {
                    "sk_visit": {"description": "Visit surrogate key."},
                },
            }
        ),
        encoding="utf-8",
    )
    inner = MetadataSchemaClient(
        index=build_metadata_column_index(dags_root=tmp_path / "dags")
    )
    client = DataHubFallbackSchemaClient(
        inner=inner,
        probe=DataHubSchemaProbe(
            post=_fake_post_factory(
                existing_urns={_SANDBOX_URN},
                schema_by_urn={_SANDBOX_URN: ["sk_nps_answer"]},
            ),
            token="token",
        ),
    )
    assert client.table_exists("sandbox", "nps_fr")
    assert client.column_names_for_table("sandbox", "nps_fr") == {"sk_nps_answer"}
    assert client.table_source_hint("sandbox", "nps_fr").startswith(
        "resolved via DataHub catalog"
    )


def test_validate_golden_query_sql_sandbox_table_via_datahub_fallback(tmp_path: Path):
    inner = MetadataSchemaClient(index={})
    client = DataHubFallbackSchemaClient(
        inner=inner,
        probe=DataHubSchemaProbe(
            post=_fake_post_factory(
                existing_urns={_SANDBOX_URN},
                schema_by_urn={_SANDBOX_URN: ["sk_nps_answer"]},
            ),
            token="token",
        ),
    )
    errors, warnings = validate_golden_query_sql(
        "SELECT sk_nps_answer FROM sandbox.nps_fr",
        query_label="Query 3",
        client=client,
    )
    assert errors == []
    assert warnings == []


def _flaky_post_factory(
    *,
    transient_statuses: list[str],
    schema_by_urn: dict[str, list[str]],
    calls: list[str],
) -> Callable[..., tuple[dict | None, str]]:
    """Fail the first ``len(transient_statuses)`` schema fetches, then succeed."""
    inner = _fake_post_factory(
        existing_urns=set(schema_by_urn), schema_by_urn=schema_by_urn
    )
    pending = list(transient_statuses)

    def _post(_url, _token, query, variables, _timeout: float = 60.0):
        calls.append(query)
        if "schemaMetadata" in query and pending:
            return (None, pending.pop(0))
        return inner(_url, _token, query, variables, _timeout)

    return _post


def test_datahub_probe_retries_transient_post_failures():
    calls: list[str] = []
    slept: list[float] = []
    probe = DataHubSchemaProbe(
        post=_flaky_post_factory(
            transient_statuses=["fetch_error", "http_error"],
            schema_by_urn={_SANDBOX_URN: ["sk_nps_answer"]},
            calls=calls,
        ),
        token="token",
        sleep=slept.append,
    )
    assert probe.column_names_for_table("sandbox", "nps_fr") == {"sk_nps_answer"}
    assert len([q for q in calls if "schemaMetadata" in q]) == 3
    assert slept == [0.5, 1.0]


def test_datahub_probe_gives_up_after_persistent_transient_failures():
    calls: list[str] = []
    probe = DataHubSchemaProbe(
        post=_flaky_post_factory(
            transient_statuses=["fetch_error"] * 5,
            schema_by_urn={_SANDBOX_URN: ["sk_nps_answer"]},
            calls=calls,
        ),
        token="token",
        sleep=lambda _delay: None,
    )
    assert probe.column_names_for_table("sandbox", "nps_fr") is None
    assert len([q for q in calls if "schemaMetadata" in q]) == 3


def test_datahub_probe_does_not_retry_graphql_errors():
    calls: list[str] = []
    probe = DataHubSchemaProbe(
        post=_flaky_post_factory(
            transient_statuses=["graphql_error"],
            schema_by_urn={_SANDBOX_URN: ["sk_nps_answer"]},
            calls=calls,
        ),
        token="token",
        sleep=lambda _delay: None,
    )
    assert probe.column_names_for_table("sandbox", "nps_fr") is None
    assert len([q for q in calls if "schemaMetadata" in q]) == 1


def test_build_datahub_fallback_client_noop_without_credentials(tmp_path: Path):
    inner = MetadataSchemaClient(index={})
    wrapped = build_datahub_fallback_client(
        inner, graphql_url="", token="", post=lambda *a, **k: ({}, "ok")
    )
    assert wrapped is inner
