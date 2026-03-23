"""
Unit tests for load_api_ingestion_declaration and dag_name validation.
"""

from unittest.mock import mock_open

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
