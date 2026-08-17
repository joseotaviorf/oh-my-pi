from argparse import Namespace
from unittest.mock import MagicMock, patch

import pytest

from bietlejuice.shared.agents.writer import write_delta_or_dev_view


def _args(run_mode: str) -> Namespace:
    return Namespace(run_mode=run_mode, table_name="tier_metric_events")


def test_write_delta_or_dev_view_dev_registers_temp_view():
    result_df = MagicMock()
    logger = MagicMock()

    write_delta_or_dev_view(
        spark_client=MagicMock(),
        result_df=result_df,
        args=_args("dev"),
        merge_on=("id_metric_event",),
        partition_by=("year", "month"),
        row_count=3,
        logger=logger,
        view_suffix="events",
    )

    result_df.createOrReplaceTempView.assert_called_once_with(
        "dev_tier_metric_events_events"
    )


@pytest.mark.parametrize("run_mode", ["prod", "write"])
@patch("bietlejuice.shared.agents.writer.UnityCatalogHelper")
@patch("bietlejuice.shared.agents.writer.TablePrivileges")
@patch("bietlejuice.shared.agents.writer.DeltaLoader")
@patch("bietlejuice.shared.agents.writer.MetastoreServiceFactory")
@patch("bietlejuice.shared.agents.writer.resolve_write_target")
def test_write_delta_or_dev_view_lake_modes_merge(
    resolve_write_target,
    metastore_factory,
    delta_loader,
    table_privileges,
    unity_catalog_helper,
    run_mode,
):
    resolve_write_target.return_value = (
        "db.tier_metric_events",
        "s3://bucket/tier_metric_events",
        "db",
        "tier_metric_events",
    )
    unity_catalog_helper.is_cluster_unity_catalog_enabled.return_value = False
    result_df = MagicMock()
    spark_client = MagicMock()
    spark_client.conn = MagicMock()

    write_delta_or_dev_view(
        spark_client=spark_client,
        result_df=result_df,
        args=_args(run_mode),
        merge_on=("id_metric_event",),
        partition_by=("year", "month"),
        row_count=3,
        logger=MagicMock(),
        view_suffix="events",
    )

    result_df.createOrReplaceTempView.assert_not_called()
    delta_loader.return_value.load_table.assert_called_once()
    table_privileges.from_environment_default.assert_called_once_with(
        "db.tier_metric_events"
    )


def test_write_delta_or_dev_view_rejects_unknown_mode():
    with pytest.raises(ValueError, match="Invalid run_mode"):
        write_delta_or_dev_view(
            spark_client=MagicMock(),
            result_df=MagicMock(),
            args=_args("staging"),
            merge_on=("id_metric_event",),
            partition_by=("year", "month"),
            row_count=0,
            logger=MagicMock(),
            view_suffix="events",
        )
