import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from scripts.governance_metadata_validation.pii_privacy_checks import (  # noqa: E402
    effective_requires_mask,
    load_pii_catalog_types,
    resolve_effective_subjects,
    subjects_compatible,
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


def test_subjects_compatible_superset():
    assert subjects_compatible(["customer", "employee"], ["customer"])
    assert subjects_compatible(["employee"], ["employee"])
    assert not subjects_compatible(["employee"], ["customer"])


def test_resolve_effective_subjects_table_then_column():
    metadata = {
        "privacy": {"dataSubjectType": ["employee"]},
        "columns": {
            "work_email": {
                "privacy": {"piiType": "corporate_email"},
            }
        },
    }
    subjects = resolve_effective_subjects(metadata, metadata["columns"]["work_email"])
    assert subjects == ["employee"]


def test_resolve_effective_subjects_column_override():
    metadata = {
        "privacy": {"dataSubjectType": ["customer", "employee"]},
        "columns": {
            "work_email": {
                "privacy": {
                    "piiType": "corporate_email",
                    "dataSubjectType": ["employee"],
                },
            }
        },
    }
    subjects = resolve_effective_subjects(metadata, metadata["columns"]["work_email"])
    assert subjects == ["employee"]


def test_validate_valid_cpf(catalog_types):
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

    errors = validate_metadata_privacy(metadata, catalog_types)

    assert errors == []


def test_validate_table_level_subject_column_pii_type_only(catalog_types):
    metadata = {
        "database_name": "datalake_example_clean",
        "table_name": "person",
        "privacy": {"dataSubjectType": ["customer"]},
        "columns": {
            "cpf": {
                "description": "Brazilian CPF.",
                "privacy": {"piiType": "cpf"},
            }
        },
    }

    errors = validate_metadata_privacy(metadata, catalog_types)

    assert errors == []


def test_validate_missing_table_privacy_passes_when_no_privacy(catalog_types):
    metadata = {
        "database_name": "datalake_example_clean",
        "table_name": "person",
        "columns": {
            "id": {
                "description": "Surrogate key.",
            }
        },
    }

    errors = validate_metadata_privacy(metadata, catalog_types)

    assert errors == []


def test_validate_legacy_column_level_subject_with_table(catalog_types):
    metadata = {
        "database_name": "datalake_example_clean",
        "table_name": "person",
        "privacy": {"dataSubjectType": ["customer"]},
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

    errors = validate_metadata_privacy(metadata, catalog_types)

    assert errors == []


def test_validate_json_paths_only_column(catalog_types):
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

    errors = validate_metadata_privacy(metadata, catalog_types)

    assert errors == []


def test_validate_json_paths_inherit_table_subject(catalog_types):
    metadata = {
        "database_name": "datalake_example_clean",
        "table_name": "person",
        "privacy": {"dataSubjectType": ["customer"]},
        "columns": {
            "person_payload": {
                "description": "JSON document from the source API.",
                "privacy": {
                    "jsonPaths": [
                        {
                            "path": "$.holder.cpf",
                            "piiType": "cpf",
                        }
                    ]
                },
            }
        },
    }

    errors = validate_metadata_privacy(metadata, catalog_types)

    assert errors == []


def test_validate_json_path_errors_not_duplicated(catalog_types):
    metadata = {
        "database_name": "datalake_example_clean",
        "table_name": "person",
        "privacy": {"dataSubjectType": ["customer"]},
        "columns": {
            "person_payload": {
                "description": "JSON document.",
                "privacy": {
                    "jsonPaths": [
                        {
                            "path": "$.holder.cpf",
                            "piiType": "not_in_catalog_slug",
                        }
                    ]
                },
            }
        },
    }

    errors = validate_metadata_privacy(metadata, catalog_types)

    pii_type_errors = [e for e in errors if "not in pii_catalog" in e]
    assert len(pii_type_errors) == 1


def test_validate_table_column_subject_conflict(catalog_types):
    metadata = {
        "database_name": "datalake_example_clean",
        "table_name": "person",
        "privacy": {"dataSubjectType": ["customer"]},
        "columns": {
            "work_email": {
                "description": "Work email.",
                "privacy": {
                    "piiType": "corporate_email",
                    "dataSubjectType": ["employee"],
                },
            }
        },
    }

    errors = validate_metadata_privacy(metadata, catalog_types)

    assert any("conflicts with table" in e for e in errors)
