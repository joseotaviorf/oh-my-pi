"""
Unit tests for source_resolver: layer-aware source and universe resolution.
"""

import pytest

from bietlejuice.qube.jobs.common.conf import Config
from bietlejuice.qube.jobs.common.source_resolver import (
    SourceLayerError,
    infer_layer_from_schema,
    resolve_source,
    resolve_universe,
)


@pytest.fixture
def conf():
    return Config(env="test", config_root="qube")


class TestInferLayerFromSchema:
    """Tests for infer_layer_from_schema."""

    @pytest.mark.parametrize(
        "schema,expected",
        [
            ("clean_ebdb", "clean"),
            ("enrich_visit", "enrich"),
            ("dw_rent", "dw"),
            ("metric_rent", "metric"),
            ("core_contract", "core"),
            ("qube_dimensions", "qube"),
            ("qube_measures", "qube"),
            ("qube_metrics", "qube"),
            ("raw_ebdb", "raw"),
        ],
    )
    def test_prefix_inference(self, schema, expected):
        assert infer_layer_from_schema(schema) == expected

    @pytest.mark.parametrize(
        "schema,expected",
        [
            # QuintoAndar datalake schemas encode the layer as a suffix.
            ("datalake_ebdb_clean", "clean"),
            ("datalake_copilot_service_clean", "clean"),
            ("datalake_ebdb_raw", "raw"),
            ("datalake_access_logs_raw", "raw"),
            ("datalake_ebdb_transactional", "transactional"),
            # Bare datalake_<context> is the legacy enrich drop-prefix landing zone.
            ("datalake_ebdb", "enrich"),
            ("datalake_amplitude_visit", "enrich"),
        ],
    )
    def test_datalake_suffix_inference(self, schema, expected):
        assert infer_layer_from_schema(schema) == expected

    def test_unknown_schema_returns_none(self):
        assert infer_layer_from_schema("sandbox_whatever") is None

    def test_empty_schema_returns_none(self):
        assert infer_layer_from_schema("") is None


class TestResolveSourceBackwardCompatible:
    """Backward-compatible behavior: default Core resolution unchanged."""

    def test_auto_derived_table_uses_core_default(self, conf):
        source = {"date_expr": "unix_timestamp(dt_visit)"}
        resolved = resolve_source(conf, source, "visit")

        assert resolved.table == conf.get_table_path("core", "core_visit.visit")
        assert resolved.entity_id_col == "id_visit"
        assert resolved.layer == "core"

    def test_explicit_table_with_dot_passthrough(self, conf):
        source = {
            "table": "custom_schema.custom_table",
            "date_expr": "unix_timestamp(dt_visit)",
        }
        resolved = resolve_source(conf, source, "visit")

        # custom_schema does not match any known layer prefix -> defaults to core
        assert resolved.layer == "core"
        assert "custom_schema.custom_table" in resolved.table

    def test_explicit_entity_id_col_overrides_default(self, conf):
        source = {
            "entity_id_col": "custom_id",
            "date_expr": "unix_timestamp(dt_visit)",
        }
        resolved = resolve_source(conf, source, "visit")
        assert resolved.entity_id_col == "custom_id"


class TestResolveSourceLayerAware:
    """New behavior: sources from any allowed governed layer."""

    def test_structured_reference_with_explicit_layer(self, conf):
        source = {
            "layer": "dw",
            "source_schema": "dw_rent",
            "table_name": "dim_contract",
            "date_expr": "unix_timestamp(ts_updated)",
        }
        resolved = resolve_source(conf, source, "contract")

        assert resolved.layer == "dw"
        assert "dw_rent.dim_contract" in resolved.table

    def test_layer_inferred_from_schema_when_omitted(self, conf):
        source = {
            "table": "enrich_visit.visit_events",
            "date_expr": "unix_timestamp(ts_created)",
        }
        resolved = resolve_source(conf, source, "visit")
        assert resolved.layer == "enrich"

    def test_clean_layer_allowed(self, conf):
        source = {
            "table": "clean_ebdb.visit_log",
            "date_expr": "unix_timestamp(ts_created)",
        }
        resolved = resolve_source(conf, source, "visit")
        assert resolved.layer == "clean"

    def test_metric_layer_allowed(self, conf):
        source = {
            "table": "metric_rent.contract_metric",
            "date_expr": "unix_timestamp(ts_created)",
        }
        resolved = resolve_source(conf, source, "contract")
        assert resolved.layer == "metric"

    def test_qube_layer_allowed_for_intra_qube_reads(self, conf):
        source = {
            "table": "qube_measures.visit_unique_1d",
            "date_expr": "unix_timestamp(date)",
        }
        resolved = resolve_source(conf, source, "visit")
        assert resolved.layer == "qube"

    def test_raw_layer_rejected(self, conf):
        source = {
            "table": "raw_ebdb.visit",
            "date_expr": "unix_timestamp(ts_created)",
        }
        with pytest.raises(SourceLayerError, match="Raw layer"):
            resolve_source(conf, source, "visit")

    def test_raw_datalake_without_explicit_layer_is_rejected(self, conf):
        # Regression: a datalake_*_raw source with no explicit layer must be
        # inferred as raw and rejected, not silently defaulted to core.
        source = {
            "table": "datalake_ebdb_raw.visit",
            "date_expr": "unix_timestamp(ts_created)",
        }
        with pytest.raises(SourceLayerError, match="Raw layer"):
            resolve_source(conf, source, "visit")

    def test_clean_datalake_without_explicit_layer_is_allowed(self, conf):
        source = {
            "table": "datalake_ebdb_clean.visit",
            "date_expr": "unix_timestamp(ts_updated)",
        }
        resolved = resolve_source(conf, source, "visit")
        assert resolved.layer == "clean"

    def test_explicit_raw_layer_rejected_even_with_other_schema(self, conf):
        source = {
            "layer": "raw",
            "table": "enrich_visit.visit_events",
            "date_expr": "unix_timestamp(ts_created)",
        }
        with pytest.raises(SourceLayerError, match="Raw layer"):
            resolve_source(conf, source, "visit")

    def test_unknown_layer_rejected(self, conf):
        source = {
            "layer": "wonka",
            "table": "wonka_x.y",
            "date_expr": "unix_timestamp(ts_created)",
        }
        with pytest.raises(SourceLayerError, match="not allowed"):
            resolve_source(conf, source, "visit")


class TestResolveUniverse:
    """Tests for resolve_universe (closed-world join table resolution)."""

    def test_default_universe_is_core_entity_table(self, conf):
        universe_table, universe_entity_id_col = resolve_universe(
            conf, {}, "visit", "id_visit"
        )
        assert universe_table == conf.get_table_path("core", "core_visit.visit")
        assert universe_entity_id_col == "id_visit"

    def test_explicit_universe_table_and_entity_id_col(self, conf):
        source = {
            "universe_table": "dw_rent.dim_contract",
            "universe_entity_id_col": "id_contract",
        }
        universe_table, universe_entity_id_col = resolve_universe(
            conf, source, "contract", "id_contract"
        )
        assert "dw_rent.dim_contract" in universe_table
        assert universe_entity_id_col == "id_contract"

    def test_universe_entity_id_col_defaults_to_source_entity_id_col(self, conf):
        source = {"universe_table": "dw_rent.dim_contract"}
        _, universe_entity_id_col = resolve_universe(
            conf, source, "contract", "id_contract"
        )
        assert universe_entity_id_col == "id_contract"

    def test_universe_raw_layer_rejected(self, conf):
        source = {"universe_table": "raw_ebdb.contract", "universe_layer": "raw"}
        with pytest.raises(SourceLayerError, match="Raw layer"):
            resolve_universe(conf, source, "contract", "id_contract")
