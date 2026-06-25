import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from scripts.governance_metadata_validation.lineage_privacy_validator import (  # noqa: E402
    validate_metadata_lineage_privacy,
)


def test_lineage_pii_type_mismatch_is_error():
    entity_index = {
        "datalake_src_clean.person.cpf": {
            "piiType": "cpf",
            "dataSubjectType": ["customer"],
        }
    }
    table_subjects_index = {
        ("datalake_src_clean", "person"): ["customer"],
        ("datalake_dst_enrich", "person_enriched"): ["customer"],
    }
    metadata = {
        "database_name": "datalake_dst_enrich",
        "table_name": "person_enriched",
        "privacy": {"dataSubjectType": ["customer"]},
        "columns": {
            "cpf": {
                "lineage": ["datalake_src_clean.person.cpf"],
                "privacy": {"piiType": "rg"},
            }
        },
    }

    errors, warnings = validate_metadata_lineage_privacy(
        metadata,
        entity_index,
        table_subjects_index,
        "test.yml",
    )

    assert len(errors) == 1
    assert "diverges from upstream" in errors[0]
    assert warnings == []


def test_lineage_pending_upstream_is_warning():
    metadata = {
        "database_name": "datalake_dst_enrich",
        "table_name": "person_enriched",
        "privacy": {"dataSubjectType": ["customer"]},
        "columns": {
            "cpf": {
                "lineage": ["datalake_src_clean.person.cpf"],
                "privacy": {"piiType": "cpf"},
            }
        },
    }

    errors, warnings = validate_metadata_lineage_privacy(metadata, {}, {}, "test.yml")

    assert errors == []
    assert len(warnings) == 1
    assert "pending_upstream" in warnings[0]


def test_lineage_pending_upstream_is_warning_when_table_privacy_exists():
    entity_index = {}
    table_subjects_index = {
        ("datalake_src_clean", "person"): ["customer"],
    }
    metadata = {
        "database_name": "datalake_dst_enrich",
        "table_name": "person_enriched",
        "columns": {
            "cpf": {
                "lineage": ["datalake_src_clean.person.cpf"],
                "privacy": {"piiType": "cpf", "dataSubjectType": ["customer"]},
            }
        },
    }

    errors, warnings = validate_metadata_lineage_privacy(
        metadata,
        entity_index,
        table_subjects_index,
        "test.yml",
    )

    assert errors == []
    assert len(warnings) == 1
    assert "pending_upstream" in warnings[0]


def test_lineage_table_subject_mismatch_when_pending_upstream():
    entity_index = {}
    table_subjects_index = {
        ("datalake_src_clean", "person"): ["employee"],
        ("datalake_dst_enrich", "person_enriched"): ["customer"],
    }
    metadata = {
        "database_name": "datalake_dst_enrich",
        "table_name": "person_enriched",
        "privacy": {"dataSubjectType": ["customer"]},
        "columns": {
            "cpf": {
                "lineage": ["datalake_src_clean.person.cpf"],
                "privacy": {"piiType": "cpf"},
            }
        },
    }

    errors, warnings = validate_metadata_lineage_privacy(
        metadata,
        entity_index,
        table_subjects_index,
        "test.yml",
    )

    assert len(errors) == 1
    assert "incompatible" in errors[0]
    assert len(warnings) == 1
    assert "pending_upstream" in warnings[0]


def test_lineage_jsonpaths_only_emits_warning():
    metadata = {
        "database_name": "datalake_dst_enrich",
        "table_name": "person_enriched",
        "columns": {
            "person_payload": {
                "lineage": ["datalake_src_clean.person.person_payload"],
                "privacy": {
                    "jsonPaths": [
                        {"path": "$.holder.cpf", "piiType": "cpf"},
                    ],
                    "dataSubjectType": ["customer"],
                },
            }
        },
    }

    errors, warnings = validate_metadata_lineage_privacy(metadata, {}, {}, "test.yml")

    assert errors == []
    assert any("jsonPaths lineage is not validated yet" in w for w in warnings)
