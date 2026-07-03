"""Unit tests for SyncMetadataTaskCreator timeout passthrough and incremental flag."""

from unittest.mock import MagicMock

from bietlejuice.base.airflow.task_creators.sync_metadata_task_creator import (
    SyncMetadataTaskCreator,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.layer_enum import LayerEnum

PARTITION_VALUES_TEMPLATE = (
    '[["{{ data_interval_start.year }}", '
    '"{{ data_interval_start.month }}", '
    '"{{ data_interval_start.day }}"]]'
)


def make_creator(workflow_args):
    ctx = MagicMock()
    ctx.bucket = "test-bucket"
    ctx.dag_args = {"name": "emlio"}
    ctx.workflow_args = workflow_args
    creator = SyncMetadataTaskCreator(ctx)
    creator._create_spark_job_task = MagicMock(name="_create_spark_job_task")
    return creator


def make_table_attributes(layer, workflow_args):
    return TableAttributes(
        dag_args={"name": "emlio"},
        workflow_args=workflow_args,
        layer=layer,
        table_name="emlio_logs",
    )


class TestExecutionTimeoutPassthrough:
    def test_declared_workflow_timeout_is_passed(self):
        workflow_args = {"execution_timeout_hours": 6}
        creator = make_creator(workflow_args)

        creator.create_task(make_table_attributes(LayerEnum.RAW, workflow_args))

        kwargs = creator._create_spark_job_task.call_args.kwargs
        assert kwargs["execution_timeout_hours"] == 6

    def test_default_timeout_when_not_declared(self):
        creator = make_creator({})

        creator.create_task(make_table_attributes(LayerEnum.RAW, {}))

        kwargs = creator._create_spark_job_task.call_args.kwargs
        assert kwargs["execution_timeout_hours"] == 2

    def test_table_customization_overrides_workflow_timeout(self):
        workflow_args = {
            "execution_timeout_hours": 6,
            "tables_customization": {"emlio_logs": {"execution_timeout_hours": 3}},
        }
        creator = make_creator(workflow_args)

        creator.create_task(make_table_attributes(LayerEnum.RAW, workflow_args))

        kwargs = creator._create_spark_job_task.call_args.kwargs
        assert kwargs["execution_timeout_hours"] == 3


class TestIncrementalPartitionSyncFlag:
    def test_raw_layer_with_flag_appends_partition_values(self):
        workflow_args = {"incremental_partition_sync": True}
        creator = make_creator(workflow_args)

        creator.create_task(make_table_attributes(LayerEnum.RAW, workflow_args))

        params = creator._create_spark_job_task.call_args.args[2]
        assert params[-2:] == ["--partition-values", PARTITION_VALUES_TEMPLATE]

    def test_clean_layer_with_flag_does_not_append(self):
        workflow_args = {"incremental_partition_sync": True}
        creator = make_creator(workflow_args)

        creator.create_task(make_table_attributes(LayerEnum.CLEAN, workflow_args))

        params = creator._create_spark_job_task.call_args.args[2]
        assert "--partition-values" not in params

    def test_raw_layer_without_flag_does_not_append(self):
        creator = make_creator({})

        creator.create_task(make_table_attributes(LayerEnum.RAW, {}))

        params = creator._create_spark_job_task.call_args.args[2]
        assert "--partition-values" not in params
