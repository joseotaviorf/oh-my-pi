import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from scripts.governance_metadata_validation.pii_privacy_checks import (  # noqa: E402
    effective_requires_mask,
    load_pii_catalog_types,
    validate_metadata_privacy,
)


@pytest.fixture
def catalog_types():
    return load_pii_catalog_types()


@pytest.mark.parametrize(
    "data_subject_types, expected",
    [
        (["customer"], True),
        (["customer", "employee"], True),
        (["employee"], False),
        (["partner"], False),
        ([], False),
    ],
)
def test_effective_requires_mask(data_subject_types, expected):
    # Act
    result = effective_requires_mask(data_subject_types)

    # Assert
    assert result is expected


def test_validate_valid_cpf(catalog_types):
    # Arrange
    metadata = {
        "database_name": "datalake_example_clean",
        "table_name": "person",
        "columns": {
            "cpf": {
                "description": "Brazilian CPF.",
                "privacy": {
                    "piiType": "cpf",
                    "dataSubjectType": ["customer"],
                },
            }
        },
    }

    # Act
    errors = validate_metadata_privacy(metadata, catalog_types)

    # Assert
    assert errors == []


def test_validate_json_paths_only_column(catalog_types):
    # Arrange
    metadata = {
        "database_name": "datalake_example_clean",
        "table_name": "person",
        "columns": {
            "person_payload": {
                "description": "JSON document from the source API.",
                "privacy": {
                    "jsonPaths": [
                        {
                            "path": "$.holder.cpf",
                            "piiType": "cpf",
                            "dataSubjectType": ["customer"],
                        }
                    ]
                },
            }
        },
    }

    # Act
    errors = validate_metadata_privacy(metadata, catalog_types)

    # Assert
    assert errors == []


def test_validate_json_path_errors_not_duplicated(catalog_types):
    # Arrange
    metadata = {
        "database_name": "datalake_example_clean",
        "table_name": "person",
        "columns": {
            "person_payload": {
                "description": "JSON document.",
                "privacy": {
                    "jsonPaths": [
                        {
                            "path": "$.holder.cpf",
                            "piiType": "not_in_catalog_slug",
                            "dataSubjectType": ["customer"],
                        }
                    ]
                },
            }
        },
    }

    # Act
    errors = validate_metadata_privacy(metadata, catalog_types)

    # Assert
    pii_type_errors = [e for e in errors if "not in pii_catalog" in e]
    assert len(pii_type_errors) == 1
