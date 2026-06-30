"""Unit tests for the metric-product relaxation in the DataHub curated-entity loader.

Metric Data Products (``data_product_type: metric``) are calculations over tables owned
by domain products — they own no base tables of their own. These tests pin the loader's
network-free decision logic so the relaxation can't regress:

  * ``_is_metric_product`` classifies by ``data_product_type``
  * ``_curated_data_product_asset_urns`` returns ``[]`` for a metric with no ``datasets``
    (instead of raising), while a non-metric with no ``datasets`` is still a hard error.
"""

import sys
from pathlib import Path

import pytest

_DATAHUB_CTX = (
    Path(__file__).resolve().parents[3] / "dags/governance/datahub_business_context"
)
sys.path.insert(0, str(_DATAHUB_CTX))

import load_collections_context as loader  # noqa: E402


class TestIsMetricProduct:
    def test_metric_type_is_true(self) -> None:
        assert loader._is_metric_product({"data_product_type": "metric"}) is True

    def test_metric_type_is_case_and_space_insensitive(self) -> None:
        assert loader._is_metric_product({"data_product_type": "  Metric "}) is True

    def test_domain_type_is_false(self) -> None:
        assert loader._is_metric_product({"data_product_type": "domain"}) is False

    def test_missing_type_is_false(self) -> None:
        assert loader._is_metric_product({}) is False


class TestCuratedDataProductAssetUrns:
    @pytest.mark.parametrize(
        "cfg",
        [
            {"data_product_type": "metric"},
            {"data_product_type": "metric", "datasets": []},
            {"data_product_type": "metric", "datasets": None},
        ],
    )
    def test_metric_with_no_datasets_returns_empty(self, cfg: dict) -> None:
        # Metric products own no base tables — empty is valid, never raises.
        assert loader._curated_data_product_asset_urns(cfg) == []

    @pytest.mark.parametrize(
        "cfg",
        [
            {"data_product_type": "domain"},
            {"data_product_type": "domain", "datasets": []},
            {},
        ],
    )
    def test_non_metric_with_no_datasets_raises(self, cfg: dict) -> None:
        with pytest.raises(SystemExit):
            loader._curated_data_product_asset_urns(cfg)

    def test_explicit_urn_row_is_passed_through(self) -> None:
        # An explicit-URN dataset row needs no platform probing (no network).
        urn = "urn:li:dataset:(urn:li:dataPlatform:trino,hive.s.t,PROD)"
        cfg = {"data_product_type": "metric", "datasets": [{"urn": urn}]}
        assert loader._curated_data_product_asset_urns(cfg) == [urn]


class TestTableRefsInSql:
    """Subject auto-derivation: parse schema.table refs from golden-query SQL."""

    def test_extracts_from_and_join_refs(self) -> None:
        sql = """
        WITH actual_vol AS (
            SELECT * FROM dw_growth.obt_supply
            LEFT JOIN datalake_wololo_clean.prospect_aud ON 1=1
        )
        SELECT * FROM actual_vol
        INNER JOIN dw_sale.fact_listings AS fl ON fl.id = actual_vol.id
        """
        refs = loader._table_refs_in_sql(sql)
        assert ("dw_growth", "obt_supply") in refs
        assert ("datalake_wololo_clean", "prospect_aud") in refs
        assert ("dw_sale", "fact_listings") in refs

    def test_ignores_cte_aliases_and_subqueries(self) -> None:
        sql = "SELECT * FROM actual_vol JOIN aux ON 1=1 WHERE x IN (SELECT y FROM (VALUES 1))"
        # Bare CTE aliases (no schema qualifier) must not be treated as tables.
        assert loader._table_refs_in_sql(sql) == []

    def test_dedupes_repeated_refs_preserving_order(self) -> None:
        sql = "FROM a.one JOIN b.two JOIN a.one"
        assert loader._table_refs_in_sql(sql) == [("a", "one"), ("b", "two")]

    def test_empty_or_none_sql_is_safe(self) -> None:
        assert loader._table_refs_in_sql("") == []
        assert loader._table_refs_in_sql(None) == []


class TestAssertSafeUrl:
    """SSRF guard on request URLs (CWE-918)."""

    @pytest.mark.parametrize(
        "url",
        [
            "https://datahub-gms.apps.data-prd.habitat.zone/api/graphql",
            "https://datahub-gms.apps.data-prd.habitat.zone/aspects?action=ingestProposal",
            "http://localhost:8080/api/graphql",
            "http://127.0.0.1:8080/api/graphql",
        ],
    )
    def test_allowed_http_urls_pass_through(self, url: str) -> None:
        assert loader._assert_safe_url(url) == url

    @pytest.mark.parametrize(
        "url",
        [
            "file:///etc/passwd",
            "gopher://internal/",
            "ftp://host/x",
            "not-a-url",
            "",
            "/api/graphql",  # no scheme/host
        ],
    )
    def test_unsafe_or_non_http_urls_raise(self, url: str) -> None:
        with pytest.raises(ValueError):
            loader._assert_safe_url(url)

    @pytest.mark.parametrize(
        "url",
        [
            "https://evil.example.com/api/graphql",
            "http://169.254.169.254/latest/meta-data/",  # cloud metadata endpoint
            "https://attacker.test/aspects",
        ],
    )
    def test_disallowed_hosts_raise(self, url: str) -> None:
        with pytest.raises(ValueError):
            loader._assert_safe_url(url)


class TestGoldenQuerySubjectFallback:
    """Subject resolution order: explicit subjects -> SQL refs -> product-wide pool."""

    def test_cte_only_sql_falls_back_to_product_pool(self) -> None:
        # SQL references only a shared CTE (no schema.table) -> no network probing.
        gq = {"name": "Extraction: FL by week", "sql": "SELECT a, b FROM tb_fl"}
        pool = [
            "urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_sale.fact_listings,PROD)",
            "urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_growth.obt_supply,PROD)",
        ]
        assert loader._golden_query_subject_urns(gq, pool) == pool

    def test_no_subjects_no_pool_returns_empty(self) -> None:
        gq = {"name": "q", "sql": "SELECT a FROM tb_fl"}
        assert loader._golden_query_subject_urns(gq, None) == []
        assert loader._golden_query_subject_urns(gq, []) == []

    def test_product_subject_pool_includes_explicit_dataset_urns(self) -> None:
        urn = "urn:li:dataset:(urn:li:dataPlatform:trino,hive.s.t,PROD)"
        cfg = {"data_product_type": "metric", "datasets": [{"urn": urn}]}
        gqs = [{"name": "q", "sql": "SELECT 1 FROM cte"}]
        assert loader._product_subject_pool(cfg, gqs) == [urn]

    def test_product_subject_pool_non_metric_empty_datasets_is_safe(self) -> None:
        # _curated_data_product_asset_urns would raise SystemExit for a non-metric with no
        # datasets; the pool builder must swallow that and fall back to SQL refs only.
        cfg = {"data_product_type": "domain"}
        gqs = [{"name": "q", "sql": "SELECT 1 FROM cte"}]
        assert loader._product_subject_pool(cfg, gqs) == []


class TestPruneStaleAssets:
    """Full-overwrite: a republish detaches assets the YAML no longer lists."""

    @staticmethod
    def _fetch_response(*urns: str) -> dict:
        return {
            "dataProduct": {
                "entities": {
                    "searchResults": [{"entity": {"urn": u}} for u in urns]
                }
            }
        }

    def test_fetch_linked_asset_urns_parses_and_skips_nulls(self, monkeypatch) -> None:
        resp = {
            "dataProduct": {
                "entities": {
                    "searchResults": [
                        {"entity": {"urn": "urn:a"}},
                        {"entity": {"urn": "urn:b"}},
                        {"entity": None},  # defensive: malformed row
                        {},
                    ]
                }
            }
        }
        monkeypatch.setattr(loader, "_post", lambda q, v: resp)
        assert loader._fetch_linked_asset_urns("urn:li:dataProduct:x") == {
            "urn:a",
            "urn:b",
        }

    def test_unlinks_only_the_set_difference(self, monkeypatch) -> None:
        calls: list[tuple[str, dict]] = []

        def _post(query: str, variables: dict):
            calls.append((query, variables))
            if "FetchDataProductAssets" in query:
                return self._fetch_response("urn:a", "urn:b", "urn:c")
            return {"batchSetDataProduct": True}

        monkeypatch.setattr(loader, "_post", _post)
        loader._prune_stale_assets("urn:li:dataProduct:x", ["urn:a"])

        mutations = [v for q, v in calls if "FetchDataProductAssets" not in q]
        assert len(mutations) == 1
        inp = mutations[0]["input"]
        assert "dataProductUrn" not in inp  # null dataProductUrn => detach from product
        assert sorted(inp["resourceUrns"]) == ["urn:b", "urn:c"]

    def test_noop_when_nothing_stale(self, monkeypatch) -> None:
        calls: list[tuple[str, dict]] = []

        def _post(query: str, variables: dict):
            calls.append((query, variables))
            return self._fetch_response("urn:a") if "FetchDataProductAssets" in query else {}

        monkeypatch.setattr(loader, "_post", _post)
        loader._prune_stale_assets("urn:li:dataProduct:x", ["urn:a", "urn:extra"])
        # Only the fetch happened — no detach mutation when current ⊆ desired.
        assert all("FetchDataProductAssets" in q for q, _ in calls)

    def test_fail_open_when_lookup_fails(self, monkeypatch) -> None:
        calls: list[tuple[str, dict]] = []

        def _post(query: str, variables: dict):
            calls.append((query, variables))
            return None if "FetchDataProductAssets" in query else {"batchSetDataProduct": True}

        monkeypatch.setattr(loader, "_post", _post)
        loader._prune_stale_assets("urn:li:dataProduct:x", ["urn:a"])
        # Never detach on incomplete information (fail-open) — no mutation attempted.
        assert all("FetchDataProductAssets" in q for q, _ in calls)
