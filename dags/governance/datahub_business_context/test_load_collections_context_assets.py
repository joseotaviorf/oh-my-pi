"""Unit tests for Data Product asset linking with shared table membership.

The same dataset may sit on several Data Products. The loader still creates the
product when nothing is assignable (pending ingest or lookup failure), and it
links tables that another product already lists.
"""

from __future__ import annotations

import sys
from types import ModuleType
from typing import Any
from unittest.mock import patch


def _stub_runtime_imports_if_needed() -> None:
    """CI has the runtime venv; this Cloud Agent image does not (private logger)."""
    try:
        import quintoandar_logger  # noqa: F401

        return
    except ModuleNotFoundError:
        pass

    def _mod(name: str, **attrs: Any) -> ModuleType:
        module = sys.modules.get(name) or ModuleType(name)
        for key, value in attrs.items():
            setattr(module, key, value)
        sys.modules[name] = module
        return module

    _mod("quintoandar_logger", QuintoAndarLogger=lambda *a, **k: None)
    _mod("bietlejuice")
    _mod("bietlejuice.governance")
    _mod("bietlejuice.governance.fairness_assessment")
    _mod("bietlejuice.governance.fairness_assessment.datahub_graphql")
    _mod(
        "bietlejuice.governance.fairness_assessment.datahub_graphql.client",
        datahub_graphql_post=lambda *a, **k: (None, "stub"),
    )


_stub_runtime_imports_if_needed()

import load_collections_context as loader  # noqa: E402


class TestMayPublishWithoutLinkedAssets:
    def test_unlinked_tables_allow_zero_asset_publish(self) -> None:
        assert (
            loader._may_publish_without_linked_assets(
                is_metric=False,
                pending=[],
                unlinked=["dw_visit.fact_visits"],
            )
            is True
        )

    def test_pending_tables_allow_zero_asset_publish(self) -> None:
        assert (
            loader._may_publish_without_linked_assets(
                is_metric=False,
                pending=["dw_sale_primary_market.dim_house_development"],
                unlinked=[],
            )
            is True
        )

    def test_metric_allows_zero_asset_publish(self) -> None:
        assert (
            loader._may_publish_without_linked_assets(
                is_metric=True, pending=[], unlinked=[]
            )
            is True
        )

    def test_empty_domain_with_nothing_to_note_does_not_publish(self) -> None:
        assert (
            loader._may_publish_without_linked_assets(
                is_metric=False, pending=[], unlinked=[]
            )
            is False
        )


class TestAppendDatasetNotes:
    def test_unlinked_sentinel_is_appended(self) -> None:
        desc = loader._append_dataset_notes(
            "Primary Market classification.",
            pending=[],
            unlinked=["dw_visit.fact_visits"],
        )
        assert loader._UNLINKED_TABLES_SENTINEL in desc
        assert "`dw_visit.fact_visits`" in desc
        assert loader._PENDING_TABLES_SENTINEL not in desc

    def test_pending_sentinel_is_appended(self) -> None:
        desc = loader._append_dataset_notes(
            "Primary Market classification.",
            pending=["datalake_sale_primary_market.listing_sale_type"],
            unlinked=[],
        )
        assert loader._PENDING_TABLES_SENTINEL in desc
        assert "`datalake_sale_primary_market.listing_sale_type`" in desc


class TestCuratedUnlinkedDatasetNames:
    def test_registered_but_not_assigned_tables_are_unlinked(self) -> None:
        cfg = {
            "datasets": [
                {"schema": "dw_visit", "table": "fact_visits"},
                {
                    "schema": "datalake_sale_primary_market",
                    "table": "listing_sale_type",
                },
            ]
        }
        visits_urn = (
            "urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_visit.fact_visits,PROD)"
        )
        own_urn = (
            "urn:li:dataset:(urn:li:dataPlatform:trino,"
            "hive.datalake_sale_primary_market.listing_sale_type,PROD)"
        )

        def _resolve(schema: str, table: str) -> str | None:
            return {
                ("dw_visit", "fact_visits"): visits_urn,
                (
                    "datalake_sale_primary_market",
                    "listing_sale_type",
                ): own_urn,
            }.get((schema, table))

        with patch.object(loader, "_resolve_urn", side_effect=_resolve):
            unlinked = loader._curated_unlinked_dataset_names(cfg, {own_urn})

        assert unlinked == ["dw_visit.fact_visits"]


class TestFilterAssignableUrns:
    """Shared membership: a dataset already on another product is still assignable."""

    _THIS = "urn:li:dataProduct:primary-market"
    _OTHER = "urn:li:dataProduct:visits"
    _OWNED_ELSEWHERE = "urn:li:dataset:visits"
    _UNOWNED = "urn:li:dataset:pm"
    _ALREADY_OURS = "urn:li:dataset:already-ours"
    _LOOKUP_FAILED = "urn:li:dataset:unknown"

    def _owners(self, urn: str) -> Any:
        return {
            self._OWNED_ELSEWHERE: self._OTHER,
            self._UNOWNED: None,
            self._ALREADY_OURS: self._THIS,
            self._LOOKUP_FAILED: loader._OWNER_UNKNOWN,
        }[urn]

    def test_keeps_assets_owned_by_another_product(self) -> None:
        with patch.object(
            loader, "_get_asset_current_product_urn", side_effect=self._owners
        ):
            assignable = loader._filter_assignable_urns(
                [self._OWNED_ELSEWHERE, self._UNOWNED, self._ALREADY_OURS],
                self._THIS,
            )
        assert assignable == [
            self._OWNED_ELSEWHERE,
            self._UNOWNED,
            self._ALREADY_OURS,
        ]

    def test_lookup_failure_is_fail_closed(self) -> None:
        with patch.object(
            loader, "_get_asset_current_product_urn", side_effect=self._owners
        ):
            assignable = loader._filter_assignable_urns(
                [self._LOOKUP_FAILED], self._THIS
            )
        assert assignable == []


class TestCuratedPushAssetsSharedAndZeroAssignable:
    """Shared tables are linked; 0 assignable URNs still create the product."""

    def test_links_tables_already_on_another_product(self) -> None:
        cfg = {
            "data_product_id": "primary-market",
            "product_display_name": "Primary Market",
            "product_description": "Primary vs Secondary sale classification. " * 4,
            "domain_urn": "urn:li:domain:sale",
            "data_product_type": "domain",
            "datasets": [{"schema": "dw_visit", "table": "fact_visits"}],
        }
        visits_urn = "urn:li:dataset:visits"
        created: dict[str, Any] = {}

        def _create(
            pid: str, pname: Any, pdesc_raw: str | None, dom: Any, dp_u: str
        ) -> bool:
            created["id"] = pid
            created["description"] = pdesc_raw
            return True

        loader._errors.clear()
        with (
            patch.object(
                loader, "_curated_data_product_asset_urns", return_value=[visits_urn]
            ),
            patch.object(
                loader, "_filter_registered_dataset_urns", side_effect=lambda urns: urns
            ),
            patch.object(
                loader,
                "_get_asset_current_product_urn",
                return_value="urn:li:dataProduct:visits",
            ),
            patch.object(loader, "_curated_pending_dataset_names", return_value=[]),
            patch.object(loader, "_resolve_urn", return_value=visits_urn),
            patch.object(
                loader, "_create_or_update_data_product", side_effect=_create
            ) as create_mock,
            patch.object(loader, "_prune_stale_assets") as prune_mock,
            patch.object(loader, "_post", return_value={"ok": True}) as post_mock,
        ):
            loader.curated_push_assets(cfg)

        assert created.get("id") == "primary-market"
        assert loader._UNLINKED_TABLES_SENTINEL not in (
            created.get("description") or ""
        )
        create_mock.assert_called_once()
        prune_mock.assert_called_once()
        post_mock.assert_called_once()
        posted = post_mock.call_args.args[1]
        assert posted["input"]["resourceUrns"] == [visits_urn]
        assert not loader._errors

    def test_creates_product_when_assignable_is_empty(self) -> None:
        cfg = {
            "data_product_id": "primary-market",
            "product_display_name": "Primary Market",
            "product_description": "Primary vs Secondary sale classification. " * 4,
            "domain_urn": "urn:li:domain:sale",
            "data_product_type": "domain",
            "datasets": [{"schema": "dw_visit", "table": "fact_visits"}],
        }
        visits_urn = "urn:li:dataset:visits"
        created: dict[str, Any] = {}

        def _create(
            pid: str, pname: Any, pdesc_raw: str | None, dom: Any, dp_u: str
        ) -> bool:
            created["id"] = pid
            created["description"] = pdesc_raw
            return True

        loader._errors.clear()
        with (
            patch.object(
                loader, "_curated_data_product_asset_urns", return_value=[visits_urn]
            ),
            patch.object(
                loader, "_filter_registered_dataset_urns", side_effect=lambda urns: urns
            ),
            patch.object(loader, "_filter_assignable_urns", return_value=[]),
            patch.object(loader, "_curated_pending_dataset_names", return_value=[]),
            patch.object(loader, "_resolve_urn", return_value=visits_urn),
            patch.object(
                loader, "_create_or_update_data_product", side_effect=_create
            ) as create_mock,
            patch.object(loader, "_prune_stale_assets") as prune_mock,
            patch.object(loader, "_post") as post_mock,
        ):
            loader.curated_push_assets(cfg)

        assert created.get("id") == "primary-market"
        assert loader._UNLINKED_TABLES_SENTINEL in (created.get("description") or "")
        assert "`dw_visit.fact_visits`" in (created.get("description") or "")
        create_mock.assert_called_once()
        # Lookup failed / 0 assignable must not treat YAML-registered tables as stale.
        prune_mock.assert_called_once_with(
            "urn:li:dataProduct:primary-market", [visits_urn]
        )
        post_mock.assert_not_called()
        assert not any("no datasets from YAML" in err for err in loader._errors)


class TestPruneStaleAssetsScopedRemove:
    """Dropping a shared table from one product must not unset it globally."""

    _THIS = "urn:li:dataProduct:primary-market"
    _SHARED = "urn:li:dataset:visits"
    _OURS_ONLY = "urn:li:dataset:pm"
    _DROPPED_SHARED = "urn:li:dataset:sale"

    def test_remove_mutation_is_scoped_to_this_product(self) -> None:
        with (
            patch.object(
                loader,
                "_fetch_linked_asset_urns",
                return_value={self._SHARED, self._DROPPED_SHARED},
            ),
            patch.object(loader, "_post", return_value={"ok": True}) as post_mock,
        ):
            loader._prune_stale_assets(self._THIS, [self._SHARED, self._OURS_ONLY])

        post_mock.assert_called_once()
        query, variables = post_mock.call_args.args
        assert "batchRemoveFromDataProducts" in query
        assert "batchSetDataProduct" not in query
        assert variables["input"]["dataProductUrns"] == [self._THIS]
        assert variables["input"]["resourceUrns"] == [self._DROPPED_SHARED]

    def test_does_not_call_global_unset(self) -> None:
        with (
            patch.object(
                loader,
                "_fetch_linked_asset_urns",
                return_value={self._DROPPED_SHARED},
            ),
            patch.object(loader, "_post", return_value={"ok": True}) as post_mock,
        ):
            loader._prune_stale_assets(self._THIS, [])

        query, variables = post_mock.call_args.args
        posted_input = variables["input"]
        assert "batchSetDataProduct" not in query
        assert "dataProductUrn" not in posted_input
        assert posted_input["dataProductUrns"] == [self._THIS]
        assert posted_input["resourceUrns"] == [self._DROPPED_SHARED]

    def test_mutation_failure_is_fail_open(self) -> None:
        loader._errors.clear()
        with (
            patch.object(
                loader,
                "_fetch_linked_asset_urns",
                return_value={self._DROPPED_SHARED},
            ),
            patch.object(loader, "_post", return_value=None) as post_mock,
        ):
            loader._prune_stale_assets(self._THIS, [])

        assert not loader._errors
        query, _variables = post_mock.call_args.args
        assert "batchRemoveFromDataProducts" in query
        assert "batchSetDataProduct" not in query

    def test_no_post_when_nothing_stale(self) -> None:
        with (
            patch.object(
                loader,
                "_fetch_linked_asset_urns",
                return_value={self._SHARED},
            ),
            patch.object(loader, "_post") as post_mock,
        ):
            loader._prune_stale_assets(self._THIS, [self._SHARED])
        post_mock.assert_not_called()

    def test_push_prune_keeps_lookup_failed_yaml_tables(self) -> None:
        """Partial ownership lookup must not mark still-declared tables as stale."""
        cfg = {
            "data_product_id": "primary-market",
            "product_display_name": "Primary Market",
            "product_description": "Primary vs Secondary sale classification. " * 4,
            "domain_urn": "urn:li:domain:sale",
            "data_product_type": "domain",
            "datasets": [
                {"schema": "dw_visit", "table": "fact_visits"},
                {
                    "schema": "datalake_sale_primary_market",
                    "table": "listing_sale_type",
                },
            ],
        }
        visits_urn = "urn:li:dataset:visits"
        own_urn = "urn:li:dataset:pm"

        loader._errors.clear()
        with (
            patch.object(
                loader,
                "_curated_data_product_asset_urns",
                return_value=[visits_urn, own_urn],
            ),
            patch.object(
                loader, "_filter_registered_dataset_urns", side_effect=lambda urns: urns
            ),
            patch.object(loader, "_filter_assignable_urns", return_value=[own_urn]),
            patch.object(loader, "_curated_pending_dataset_names", return_value=[]),
            patch.object(
                loader,
                "_resolve_urn",
                side_effect=lambda schema, table: {
                    ("dw_visit", "fact_visits"): visits_urn,
                    (
                        "datalake_sale_primary_market",
                        "listing_sale_type",
                    ): own_urn,
                }.get((schema, table)),
            ),
            patch.object(loader, "_create_or_update_data_product", return_value=True),
            patch.object(loader, "_prune_stale_assets") as prune_mock,
            patch.object(loader, "_post", return_value={"ok": True}),
        ):
            loader.curated_push_assets(cfg)

        prune_mock.assert_called_once_with(
            "urn:li:dataProduct:primary-market", [visits_urn, own_urn]
        )
        assert not loader._errors
