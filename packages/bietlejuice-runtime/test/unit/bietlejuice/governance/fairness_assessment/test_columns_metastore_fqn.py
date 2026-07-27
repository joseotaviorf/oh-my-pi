"""Guard the ``columns_metastore`` snapshot read against a three-part catalog name.

Regression for the 21/07/2026 FAIR outage: after ``enrich_fairness_assessment`` moved to
the EMR fleet, the adapter still addressed the snapshot with a Unity Catalog three-part
name (``quintoandar_{env}.…``). EMR's Hive metastore has no such catalog, so the read
failed silently, the snapshot came back empty, and F1-03 flipped to
``columns_metastore_snapshot_unavailable`` for 100% of assets → ``tier_achieved=0``
(Not FAIR). Every other read in ``load_fairness_assessment`` uses a two-part Hive name;
this keeps the snapshot read aligned so it resolves on both Databricks and EMR.
"""

from bietlejuice.governance.fairness_assessment.adapters import columns_metastore_fqn
from bietlejuice.governance.fairness_assessment.constants import COLUMNS_METASTORE


def test_fqn_is_two_part_hive_name() -> None:
    db, tbl = COLUMNS_METASTORE
    assert columns_metastore_fqn() == f"{db}.{tbl}"


def test_fqn_has_no_unity_catalog_prefix() -> None:
    fqn = columns_metastore_fqn()
    # Exactly one dot => two-part (schema.table); a three-part catalog name would break EMR.
    assert fqn.count(".") == 1
    assert not fqn.startswith("quintoandar_")
    assert "quintoandar_" not in fqn
