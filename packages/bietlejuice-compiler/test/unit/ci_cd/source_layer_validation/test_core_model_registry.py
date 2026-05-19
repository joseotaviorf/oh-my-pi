# -*- coding: utf-8 -*-
"""
Unit tests for core_model_registry.build_core_model_registry.

Uses tmp_path to build minimal fake dags/core/ trees so tests are fully
isolated from the real DAG tree.
"""

import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[6]))

from scripts.ci_cd.source_layer_validation.core_model_registry import (  # noqa: E402
    build_core_model_registry,
)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------


def _write_metadata(base: Path, dag: str, table: str, content: dict) -> Path:
    """Write a fake core metadata YAML and return its path."""
    meta_dir = base / "core" / dag / "metadata" / "core"
    meta_dir.mkdir(parents=True, exist_ok=True)
    path = meta_dir / f"{table}.yml"
    path.write_text(yaml.dump(content))
    return path


# ---------------------------------------------------------------------------
# basic registration
# ---------------------------------------------------------------------------


class TestBuildCoreModelRegistry:
    def test_registers_context_defining_column(self, tmp_path):
        _write_metadata(
            tmp_path,
            "core_house",
            "house",
            {
                "database_name": "core_house",
                "table_name": "house",
                "context_defining_tables": ["datalake_ebdb_clean.house"],
                "columns": {
                    "id_house": {
                        "lineage": ["datalake_ebdb_clean.house.id"],
                        "description": "House id.",
                    }
                },
            },
        )
        registry = build_core_model_registry(tmp_path)
        assert "datalake_ebdb_clean.house.id" in registry
        entry = registry["datalake_ebdb_clean.house.id"]
        assert entry.dag_name == "core_house"
        assert entry.core_fqn == "core_house.house.id_house"

    def test_skips_column_outside_context_tables(self, tmp_path):
        _write_metadata(
            tmp_path,
            "core_contract",
            "contract",
            {
                "database_name": "core_contract",
                "table_name": "contract",
                "context_defining_tables": ["datalake_ebdb_clean.contract"],
                "columns": {
                    "id_contract": {
                        "lineage": ["datalake_ebdb_clean.contract.id"],
                        "description": "Contract id.",
                    },
                    "id_owner": {
                        "lineage": ["datalake_ebdb_clean.user.id"],
                        "description": "Owner id from user table.",
                    },
                },
            },
        )
        registry = build_core_model_registry(tmp_path)
        assert "datalake_ebdb_clean.contract.id" in registry
        assert "datalake_ebdb_clean.user.id" not in registry

    def test_skips_file_without_context_defining_tables(self, tmp_path):
        _write_metadata(
            tmp_path,
            "core_brokers",
            "brokers",
            {
                "database_name": "core_brokers",
                "table_name": "brokers",
                "columns": {
                    "id_broker": {
                        "lineage": ["datalake_company_clean.company.id"],
                        "description": "Broker id.",
                    }
                },
            },
        )
        registry = build_core_model_registry(tmp_path)
        assert registry == {}

    def test_skips_file_with_empty_context_defining_tables(self, tmp_path):
        _write_metadata(
            tmp_path,
            "core_brokers",
            "brokers",
            {
                "database_name": "core_brokers",
                "table_name": "brokers",
                "context_defining_tables": [],
                "columns": {
                    "id_broker": {
                        "lineage": ["datalake_company_clean.company.id"],
                        "description": "Broker id.",
                    }
                },
            },
        )
        registry = build_core_model_registry(tmp_path)
        assert registry == {}


# ---------------------------------------------------------------------------
# lineage entry filtering
# ---------------------------------------------------------------------------


class TestLineageEntryFiltering:
    def test_ignores_colon_lineage_entries(self, tmp_path):
        _write_metadata(
            tmp_path,
            "core_contract",
            "contract",
            {
                "database_name": "core_contract",
                "table_name": "contract",
                "context_defining_tables": ["datalake_ebdb_clean.contract"],
                "columns": {
                    "rental_administrator": {
                        "lineage": [
                            "datalake_ebdb_clean.contract.contract_rent_model:rentalAdministrator"
                        ],
                        "description": "Rental administrator.",
                    }
                },
            },
        )
        registry = build_core_model_registry(tmp_path)
        assert registry == {}

    def test_ignores_function_call_entries(self, tmp_path):
        _write_metadata(
            tmp_path,
            "core_house",
            "house",
            {
                "database_name": "core_house",
                "table_name": "house",
                "context_defining_tables": ["datalake_ebdb_clean.house"],
                "columns": {
                    "ts_load": {
                        "lineage": ["current_timestamp()"],
                        "description": "Load timestamp.",
                    }
                },
            },
        )
        registry = build_core_model_registry(tmp_path)
        assert registry == {}

    def test_ignores_two_part_lineage_entries(self, tmp_path):
        _write_metadata(
            tmp_path,
            "core_house",
            "house",
            {
                "database_name": "core_house",
                "table_name": "house",
                "context_defining_tables": ["datalake_ebdb_clean.house"],
                "columns": {
                    "id_house": {
                        "lineage": ["datalake_ebdb_clean.house"],
                        "description": "House id.",
                    }
                },
            },
        )
        registry = build_core_model_registry(tmp_path)
        assert registry == {}


# ---------------------------------------------------------------------------
# first-wins on duplicate clean FQN
# ---------------------------------------------------------------------------


class TestFirstWinsOnDuplicate:
    def test_first_core_column_wins(self, tmp_path):
        # core_contract registers contract.id first (alphabetically earlier DAG)
        _write_metadata(
            tmp_path,
            "core_contract",
            "contract",
            {
                "database_name": "core_contract",
                "table_name": "contract",
                "context_defining_tables": ["datalake_ebdb_clean.contract"],
                "columns": {
                    "id_contract": {
                        "lineage": ["datalake_ebdb_clean.contract.id"],
                        "description": "Contract id.",
                    }
                },
            },
        )
        # core_contract_extra also claims the same clean column
        _write_metadata(
            tmp_path,
            "core_contract_extra",
            "contract_extra",
            {
                "database_name": "core_contract_extra",
                "table_name": "contract_extra",
                "context_defining_tables": ["datalake_ebdb_clean.contract"],
                "columns": {
                    "id_contract_alt": {
                        "lineage": ["datalake_ebdb_clean.contract.id"],
                        "description": "Same source, different output col.",
                    }
                },
            },
        )
        registry = build_core_model_registry(tmp_path)
        # core_contract comes first alphabetically → wins
        assert registry["datalake_ebdb_clean.contract.id"].dag_name == "core_contract"
        assert (
            registry["datalake_ebdb_clean.contract.id"].core_fqn
            == "core_contract.contract.id_contract"
        )


# ---------------------------------------------------------------------------
# multi-output DAGs (brokers_history pattern)
# ---------------------------------------------------------------------------


class TestMultiOutputDag:
    def test_independent_registration_per_table(self, tmp_path):
        _write_metadata(
            tmp_path,
            "core_brokers_history",
            "brokers_history",
            {
                "database_name": "core_brokers",
                "table_name": "brokers_history",
                "context_defining_tables": ["datalake_company_transactional.company"],
                "columns": {
                    "id_event": {
                        "lineage": ["datalake_company_transactional.company.id"],
                        "description": "Event id.",
                    }
                },
            },
        )
        _write_metadata(
            tmp_path,
            "core_brokers_history",
            "broker_products_history",
            {
                "database_name": "core_brokers",
                "table_name": "broker_products_history",
                "context_defining_tables": [
                    "datalake_company_transactional.company_product"
                ],
                "columns": {
                    "id_event": {
                        "lineage": [
                            "datalake_company_transactional.company_product.id"
                        ],
                        "description": "Event id.",
                    }
                },
            },
        )
        registry = build_core_model_registry(tmp_path)
        assert "datalake_company_transactional.company.id" in registry
        assert "datalake_company_transactional.company_product.id" in registry
        assert (
            registry["datalake_company_transactional.company.id"].core_fqn
            == "core_brokers.brokers_history.id_event"
        )
        assert (
            registry["datalake_company_transactional.company_product.id"].core_fqn
            == "core_brokers.broker_products_history.id_event"
        )


# ---------------------------------------------------------------------------
# robustness
# ---------------------------------------------------------------------------


class TestRobustness:
    def test_missing_dags_core_returns_empty(self, tmp_path):
        registry = build_core_model_registry(tmp_path)
        assert registry == {}

    def test_invalid_yaml_file_is_skipped(self, tmp_path):
        meta_dir = tmp_path / "core" / "core_bad" / "metadata" / "core"
        meta_dir.mkdir(parents=True)
        (meta_dir / "bad.yml").write_text("{{invalid: yaml: :")
        # Should not raise; returns empty registry (or whatever valid files produce)
        registry = build_core_model_registry(tmp_path)
        assert isinstance(registry, dict)

    def test_column_without_lineage_is_skipped(self, tmp_path):
        _write_metadata(
            tmp_path,
            "core_house",
            "house",
            {
                "database_name": "core_house",
                "table_name": "house",
                "context_defining_tables": ["datalake_ebdb_clean.house"],
                "columns": {
                    "ts_load": {
                        "description": "Load timestamp, no lineage key.",
                    }
                },
            },
        )
        registry = build_core_model_registry(tmp_path)
        assert registry == {}
