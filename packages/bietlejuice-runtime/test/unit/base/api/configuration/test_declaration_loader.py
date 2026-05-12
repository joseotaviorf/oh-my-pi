"""
Unit tests for load_api_ingestion_declaration and dag_name validation.
"""

import sys
from unittest.mock import mock_open, patch

import pytest

from bietlejuice.base.api.configuration.declaration_loader import (
    load_api_ingestion_declaration,
    validate_api_ingestion_dag_name,
)


class TestLoadApiIngestionDeclarationValidation:
    """Ensures malicious or invalid dag_name values are rejected before any I/O."""

    def test_validate_api_ingestion_dag_name_returns_same_string(self):
        """Validated names are returned unchanged for safe downstream use."""
        assert validate_api_ingestion_dag_name("currency_api") == "currency_api"

    @pytest.mark.parametrize(
        "invalid_name",
        [
            "",
            "../x",
            "a/b",
            "DAG-1",
            "dag.name",
            "dag name",
        ],
    )
    def test_rejects_invalid_dag_name(self, invalid_name):
        """Path traversal and non-snake_case names must raise ValueError."""
        with pytest.raises(ValueError, match="Invalid dag_name"):
            load_api_ingestion_declaration(invalid_name)

    def test_accepts_snake_case_dag_name_before_lookup(self, monkeypatch):
        """Valid names reach the loader; missing file raises FileNotFoundError."""
        monkeypatch.setattr(
            "bietlejuice.base.api.configuration.declaration_loader.DAGPackagesPathService.get_dag_path",
            lambda _n: None,
        )
        monkeypatch.setattr(
            "bietlejuice.base.api.configuration.declaration_loader._load_from_installed_package",
            lambda _n: None,
        )
        monkeypatch.setattr(
            "bietlejuice.base.api.configuration.declaration_loader._load_from_s3_volume",
            lambda _n: None,
        )
        monkeypatch.setattr(
            "bietlejuice.base.api.configuration.declaration_loader._iter_dag_domain_names",
            lambda: iter(()),
        )

        with pytest.raises(FileNotFoundError, match="Could not load a valid"):
            load_api_ingestion_declaration("valid_dag_name_xyz")

    def test_invalid_yaml_mapping_exhausts_sources(self, monkeypatch):
        """Non-dict YAML on disk falls through; no valid declaration raises FileNotFoundError."""
        monkeypatch.setattr(
            "bietlejuice.base.api.configuration.declaration_loader.DAGPackagesPathService.get_dag_path",
            lambda _n: "/fake/dag_dir",
        )
        monkeypatch.setattr(
            "bietlejuice.base.api.configuration.declaration_loader.path.isfile",
            lambda p: str(p).endswith("bad_dag_declaration.yml"),
        )
        monkeypatch.setattr(
            "bietlejuice.base.api.configuration.declaration_loader._load_from_installed_package",
            lambda _n: None,
        )
        monkeypatch.setattr(
            "bietlejuice.base.api.configuration.declaration_loader._load_from_s3_volume",
            lambda _n: None,
        )
        monkeypatch.setattr(
            "bietlejuice.base.api.configuration.declaration_loader._iter_dag_domain_names",
            lambda: iter(()),
        )
        monkeypatch.setattr(
            "builtins.open",
            mock_open(read_data="[1, 2, 3]\n"),
        )

        with pytest.raises(FileNotFoundError, match="Could not load a valid"):
            load_api_ingestion_declaration("bad_dag")


class TestLoadApiIngestionDeclarationDatabricksVolumeRegression:
    """Regression: no ModuleNotFoundError when `dags` is not on sys.path (Databricks)."""

    def test_loads_from_volume_path_without_dags_module(self, tmp_path):
        """
        When DAGPackagesPathService.get_dag_path resolves a Volume-mounted path
        (as happens after the _get_line_folders Volume fallback), the loader must
        open the declaration file directly without ever importing the `dags` package.
        _load_from_installed_package must never be reached.
        """
        dag_name = "oitchau_api"
        dag_dir = tmp_path / "people" / dag_name
        dag_dir.mkdir(parents=True)
        decl_file = dag_dir / f"{dag_name}_declaration.yml"
        decl_file.write_text("workflow:\n  type: api_ingestion\n", encoding="utf-8")

        # Ensure `dags` is absent from sys.modules to simulate the Databricks env.
        original_dags = sys.modules.pop("dags", None)
        try:
            with (
                patch(
                    "bietlejuice.base.api.configuration.declaration_loader.DAGPackagesPathService.get_dag_path",
                    return_value=str(dag_dir),
                ),
                patch(
                    "bietlejuice.base.api.configuration.declaration_loader._load_from_installed_package",
                    side_effect=AssertionError(
                        "_load_from_installed_package must not be called"
                    ),
                ),
            ):
                result = load_api_ingestion_declaration(dag_name)

            assert result == {"workflow": {"type": "api_ingestion"}}
        finally:
            if original_dags is not None:
                sys.modules["dags"] = original_dags
