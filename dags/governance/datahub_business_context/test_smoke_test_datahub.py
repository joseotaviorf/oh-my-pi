"""Unit tests for the DataHub post-push smoke skip on 0-asset products."""

from __future__ import annotations

from unittest.mock import patch

import smoke_test_datahub as smoke


class TestSkipsZeroAssetCheck:
    def test_unlinked_sentinel_skips(self) -> None:
        desc = (
            "Primary Market classification.\n\n"
            f"{smoke._UNLINKED_TABLES_SENTINEL} "
            "(ownership lookup failed this run; will retry on the next publish):\n"
            "- `dw_visit.fact_visits`"
        )
        assert smoke._skips_zero_asset_check(desc) is True

    def test_pending_sentinel_skips(self) -> None:
        desc = (
            "Primary Market classification.\n\n"
            f"{smoke._PENDING_TABLES_SENTINEL} "
            "(will be linked automatically once ingested):\n"
            "- `datalake_sale_primary_market.listing_sale_type`"
        )
        assert smoke._skips_zero_asset_check(desc) is True

    def test_plain_description_does_not_skip(self) -> None:
        assert smoke._skips_zero_asset_check("Primary Market classification.") is False


class TestCountFromRelationshipsPayload:
    def test_prefers_total_field(self) -> None:
        root = {
            "data": {
                "dataProduct": {
                    "relationships": {
                        "total": 3,
                        "relationships": [{"entity": {"urn": "a"}}],
                    }
                }
            }
        }
        assert smoke._count_from_relationships_payload(root) == 3

    def test_falls_back_to_row_length(self) -> None:
        root = {
            "data": {
                "dataProduct": {
                    "relationships": {
                        "relationships": [
                            {"entity": {"urn": "a"}},
                            {"entity": {"urn": "b"}},
                        ]
                    }
                }
            }
        }
        assert smoke._count_from_relationships_payload(root) == 2


class TestFetchAssetCountRetry:
    def test_retries_when_first_count_is_zero(self) -> None:
        counts = iter([0, 2])

        def _once(_urn: str) -> int:
            return next(counts)

        with (
            patch.object(smoke, "_fetch_asset_count_once", side_effect=_once),
            patch.object(smoke.time, "sleep") as sleep_mock,
        ):
            assert smoke._fetch_asset_count("urn:li:dataProduct:primary-market") == 2
        sleep_mock.assert_called()
