# -*- coding: utf-8 -*-
"""Unit tests for source_layer_validation.layer_classifier."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from scripts.ci_cd.source_layer_validation.layer_classifier import (  # noqa: E402
    TABLE_FQN_PATTERN,
    classify_schema_to_layer,
    classify_table_fqn,
    is_layer_allowed,
    parse_table_fqn,
)


class TestParseTableFqn:
    def test_valid(self):
        assert parse_table_fqn("datalake_ebdb_clean.user") == (
            "datalake_ebdb_clean",
            "user",
        )
        assert parse_table_fqn('  "core_listing.aux__x"  ') == (
            "core_listing",
            "aux__x",
        )

    def test_invalid(self):
        assert parse_table_fqn("not_a_table") is None
        assert parse_table_fqn("a.b.c") is None
        assert parse_table_fqn("CONTRACT") is None
        assert parse_table_fqn("") is None


class TestClassifySchemaToLayer:
    def test_datalake_layers(self):
        assert classify_schema_to_layer("datalake_ebdb_raw") == "raw"
        assert classify_schema_to_layer("datalake_ebdb_clean") == "clean"
        assert (
            classify_schema_to_layer("datalake_ebdb_transactional") == "transactional"
        )
        assert (
            classify_schema_to_layer("datalake_company_transactional")
            == "transactional"
        )
        assert classify_schema_to_layer("datalake_ebdb_booking") == "enrich"
        assert classify_schema_to_layer("datalake_banking") == "enrich"

    def test_other_layers(self):
        assert classify_schema_to_layer("dw_rent") == "dw"
        assert classify_schema_to_layer("metric_rent") == "metric"
        assert classify_schema_to_layer("qube_measures") == "qube"
        assert classify_schema_to_layer("core_listing") == "core"
        assert classify_schema_to_layer("reverse_foo") == "reverse"

    def test_unknown(self):
        assert classify_schema_to_layer("hive_prod") == "unknown"


class TestClassifyTableFqn:
    def test_classify(self):
        fqn, layer, schema = classify_table_fqn("datalake_ebdb_raw.events")
        assert fqn == "datalake_ebdb_raw.events"
        assert layer == "raw"
        assert schema == "datalake_ebdb_raw"

    def test_classify_transactional_schema(self):
        fqn, layer, schema = classify_table_fqn(
            "datalake_retsuko_transactional.invoice"
        )
        assert fqn == "datalake_retsuko_transactional.invoice"
        assert layer == "transactional"
        assert schema == "datalake_retsuko_transactional"


class TestIsLayerAllowed:
    def test_allowed(self):
        assert is_layer_allowed("clean", ["clean", "core"]) is True
        assert is_layer_allowed("CORE", ["clean", "core"]) is True

    def test_denied(self):
        assert is_layer_allowed("raw", ["clean", "core"]) is False


class TestTableFqnPattern:
    def test_matches_expected(self):
        assert TABLE_FQN_PATTERN.match("datalake_ebdb_clean.house")
        assert TABLE_FQN_PATTERN.match("core_listing.aux__x")
