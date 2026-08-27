"""Tests for Qube declaration source table extraction."""

import yaml

from bietlejuice.base.dependencies.qube_source_extractor import (
    dag_id_from_declaration,
    extract_table_fqns_from_qube_source,
    extract_tables_from_qube_declaration,
    qube_table_dependencies_from_dags_root,
)


def test_extract_default_core_source():
    source = {"date_expr": "unix_timestamp(dt_visit)"}
    tables = extract_table_fqns_from_qube_source(source, "visit")
    assert tables == {"core_visit.visit"}


def test_extract_structured_source():
    source = {
        "layer": "dw",
        "source_schema": "dw_rent",
        "table_name": "dim_contract",
        "date_expr": "unix_timestamp(ts_updated)",
    }
    tables = extract_table_fqns_from_qube_source(source, "contract")
    assert tables == {"dw_rent.dim_contract"}


def test_extract_explicit_table_and_universe():
    source = {
        "table": "enrich_visit.visit_events",
        "universe_table": "core_visit.visit",
        "date_expr": "unix_timestamp(ts_created)",
    }
    tables = extract_table_fqns_from_qube_source(source, "visit")
    assert tables == {"enrich_visit.visit_events", "core_visit.visit"}


def test_extract_include_all_entities_adds_default_universe():
    # include_all_entities is a top-level qube_specs flag, passed explicitly here.
    source = {
        "table": "enrich_visit.visit_events",
        "date_expr": "unix_timestamp(ts_created)",
    }
    tables = extract_table_fqns_from_qube_source(
        source, "visit", include_all_entities=True
    )
    assert "core_visit.visit" in tables
    assert "enrich_visit.visit_events" in tables


def test_include_all_entities_defaults_false_without_universe():
    source = {
        "table": "enrich_visit.visit_events",
        "date_expr": "unix_timestamp(ts_created)",
    }
    tables = extract_table_fqns_from_qube_source(source, "visit")
    assert tables == {"enrich_visit.visit_events"}


def test_include_all_entities_top_level_adds_default_universe():
    # Regression: the flag lives at the qube_specs level (sibling of source/logic),
    # matching the runtime DimensionSpec — not inside the source block.
    declaration = {
        "dag": {"name": "qube_dimension_visit_status"},
        "workflow": {
            "type": "qube_dimension",
            "layer": "qube",
            "qube_specs": {
                "entity": "visit",
                "name": "visit_status",
                "include_all_entities": True,
                "source": {
                    "table": "enrich_visit.visit_events",
                    "date_expr": "unix_timestamp(dt_visit)",
                },
            },
        },
    }
    tables = extract_tables_from_qube_declaration(declaration)
    assert tables == {"enrich_visit.visit_events", "core_visit.visit"}


def test_include_all_entities_misplaced_in_source_is_ignored():
    # Regression: the old buggy location (inside `source`) must NOT add the default
    # universe, because the runtime never reads it from there.
    declaration = {
        "dag": {"name": "qube_dimension_visit_status"},
        "workflow": {
            "type": "qube_dimension",
            "layer": "qube",
            "qube_specs": {
                "entity": "visit",
                "name": "visit_status",
                "source": {
                    "table": "enrich_visit.visit_events",
                    "include_all_entities": True,
                    "date_expr": "unix_timestamp(dt_visit)",
                },
            },
        },
    }
    tables = extract_tables_from_qube_declaration(declaration)
    assert tables == {"enrich_visit.visit_events"}


def test_extract_from_declaration_dict():
    declaration = {
        "dag": {"name": "qube_dimension_visit_status"},
        "workflow": {
            "type": "qube_dimension",
            "layer": "qube",
            "qube_specs": {
                "entity": "visit",
                "name": "visit_status",
                "source": {
                    "table": "enrich_visit.visit_events",
                    "date_expr": "unix_timestamp(dt_visit)",
                },
            },
        },
    }
    tables = extract_tables_from_qube_declaration(declaration)
    assert tables == {"enrich_visit.visit_events"}


def test_ignores_non_qube_workflow():
    declaration = {
        "workflow": {"type": "query_delta", "layer": "enrich"},
    }
    assert extract_tables_from_qube_declaration(declaration) == set()


def test_dag_id_from_declaration():
    decl = {"dag": {"name": "qube_measure_visit_total"}}
    assert dag_id_from_declaration(decl) == "bietlejuice.qube_measure_visit_total"


def test_qube_table_dependencies_from_dags_root(tmp_path):
    qube_root = tmp_path / "dags" / "qube" / "dimensions_visit_status"
    qube_root.mkdir(parents=True)
    declaration = {
        "dag": {"name": "qube_dimension_visit_status"},
        "workflow": {
            "type": "qube_dimension",
            "layer": "qube",
            "qube_specs": {
                "entity": "visit",
                "name": "visit_status",
                "source": {
                    "table": "enrich_visit.visit_events",
                    "date_expr": "unix_timestamp(dt_visit)",
                },
            },
        },
    }
    with open(qube_root / "dimensions_visit_status_declaration.yml", "w") as f:
        yaml.dump(declaration, f)

    deps = qube_table_dependencies_from_dags_root(tmp_path / "dags")
    assert deps == {
        "bietlejuice.qube_dimension_visit_status": {"enrich_visit.visit_events"}
    }
