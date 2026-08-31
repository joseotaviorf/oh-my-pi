import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from scripts.governance_metadata_validation.validate_lineage_consistency import (  # noqa: E402
    CDC_CLEAN_INJECTED_COLUMNS,
    CDC_INJECTED_COLUMNS_BY_WORKFLOW_TYPE,
    DMS_CDC_CLEAN_INJECTED_COLUMNS,
    compare_columns,
)

CDC = set(CDC_CLEAN_INJECTED_COLUMNS)
DMS_CDC = set(DMS_CDC_CLEAN_INJECTED_COLUMNS)


def test_no_injected_columns_behaves_like_plain_set_diff():
    # Non-CDC table: injected set is empty, so the check is a straight
    # documentation ↔ SQL-output comparison in both directions.
    missing, extra = compare_columns(
        sql_columns={"id", "name"},
        metadata_columns={"id", "name"},
        injected_columns=set(),
    )
    assert missing == set()
    assert extra == set()


def test_sql_column_not_documented_is_missing_in_metadata():
    missing, extra = compare_columns(
        sql_columns={"id", "name", "email"},
        metadata_columns={"id", "name"},
        injected_columns=set(),
    )
    assert missing == {"email"}
    assert extra == set()


def test_documented_column_not_in_physical_schema_is_extra():
    missing, extra = compare_columns(
        sql_columns={"id", "name"},
        metadata_columns={"id", "name", "removed_col"},
        injected_columns=set(),
    )
    assert missing == set()
    assert extra == {"removed_col"}


def test_cdc_injected_columns_documented_passes():
    # Injected Debezium columns may be documented; that must not be flagged as extra.
    missing, extra = compare_columns(
        sql_columns={"id", "name"},
        metadata_columns={"id", "name"} | CDC,
        injected_columns=CDC,
    )
    assert missing == set()
    assert extra == set()


def test_cdc_plumbing_columns_undocumented_are_optional():
    # I1-01 no longer scores Debezium plumbing, so lineage must not require them.
    missing, extra = compare_columns(
        sql_columns={"id", "name"},
        metadata_columns={"id", "name"},
        injected_columns=CDC,
    )
    assert missing == set()
    assert extra == set()


def test_cdc_injected_columns_partially_documented_does_not_require_the_rest():
    documented_subset = {"op_cdc"}
    missing, extra = compare_columns(
        sql_columns={"id"},
        metadata_columns={"id"} | documented_subset,
        injected_columns=CDC,
    )
    assert missing == set()
    assert extra == set()


def test_extra_and_missing_reported_together():
    missing, extra = compare_columns(
        sql_columns={"id", "email"},
        metadata_columns={"id", "removed_col"},
        injected_columns=CDC,
    )
    assert missing == {"email"}
    assert extra == {"removed_col"}


def test_dms_cdc_injected_columns_undocumented_is_required():
    # dms_cdc is the second CDC variant (load_dms_cdc_clean) and injects a
    # different column set ("Op" -> "op", "event_timestamp").
    missing, extra = compare_columns(
        sql_columns={"id"},
        metadata_columns={"id"},
        injected_columns=DMS_CDC,
    )
    assert missing == DMS_CDC
    assert extra == set()


def test_both_cdc_workflow_types_are_mapped():
    # Guards against a new CDC spark job being added without wiring its injected
    # columns here (which would let those tables pass CI but fail FAIRness I1-01).
    assert CDC_INJECTED_COLUMNS_BY_WORKFLOW_TYPE == {
        "cdc": CDC_CLEAN_INJECTED_COLUMNS,
        "dms_cdc": DMS_CDC_CLEAN_INJECTED_COLUMNS,
    }
    # Injected names must be lowercase to match the physical metastore snapshot.
    for cols in CDC_INJECTED_COLUMNS_BY_WORKFLOW_TYPE.values():
        assert all(c == c.lower() for c in cols)
