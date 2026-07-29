import json
from unittest import mock

import pytest

from bietlejuice.base.airflow.enums.task_enum import TaskEnum
from bietlejuice.base.airflow.task_creators.profiling_task_creator import (
    ProfilingTaskCreator,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.airflow.task_creators.task_creator_factory import (
    TaskCreatorFactory,
)
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class TestProfilingTaskCreator:
    @pytest.fixture
    def dag_execution_context(self):
        context = mock.MagicMock()
        context.environment = "forno"
        context.execution_date = "{{ data_interval_start | ds }}"
        context.dag_args = {"name": "enrich_datahub_assets"}
        context.workflow_args = {
            "layer": "enrich",
            "custom_schema": "datahub",
            "default_partitions": ["year", "month", "day"],
            "observability": {"enabled": True},
        }
        return context

    def _table_attributes(self, context) -> TableAttributes:
        return TableAttributes(
            dag_args=context.dag_args,
            workflow_args=context.workflow_args,
            layer=LayerEnum.ENRICH,
            table_name="datahub_assets",
        )

    def test_get_parameters_opted_in(self, dag_execution_context):
        # arrange
        creator = ProfilingTaskCreator(dag_execution_context)
        table_attributes = self._table_attributes(dag_execution_context)

        # act
        parameters = creator._get_parameters(table_attributes)

        # assert — positional contract consumed by dags/cross/base/spark_jobs/profiling.py
        assert parameters[0] == "forno"
        assert parameters[1] == "{{ data_interval_start | ds }}"
        assert isinstance(parameters[2], str) and parameters[2]  # resolved database
        assert parameters[3] == "datahub_assets"
        assert parameters[4] == "enrich"
        assert json.loads(parameters[5]) == ["year", "month", "day"]
        assert parameters[6] == "false"  # column_checks default
        assert parameters[7] == "true"  # dag_enabled

    def test_get_parameters_without_observability_block(self, dag_execution_context):
        # arrange — undeclared block => dag_enabled empty (runtime uses global default)
        dag_execution_context.workflow_args.pop("observability")
        creator = ProfilingTaskCreator(dag_execution_context)
        table_attributes = self._table_attributes(dag_execution_context)

        # act
        parameters = creator._get_parameters(table_attributes)

        # assert
        assert parameters[6] == "false"
        assert parameters[7] == ""

    def test_get_parameters_observability_block_without_enabled(
        self, dag_execution_context
    ):
        # arrange — block present but enabled omitted => same as undeclared
        dag_execution_context.workflow_args["observability"] = {"column_checks": True}
        creator = ProfilingTaskCreator(dag_execution_context)
        table_attributes = self._table_attributes(dag_execution_context)

        # act
        parameters = creator._get_parameters(table_attributes)

        # assert
        assert parameters[6] == "true"
        assert parameters[7] == ""

    def test_create_task_uses_profiling_spark_job(self, dag_execution_context):
        # arrange
        creator = ProfilingTaskCreator(dag_execution_context)
        table_attributes = self._table_attributes(dag_execution_context)
        with mock.patch.object(creator, "_create_spark_job_task") as spark_job:
            # act
            creator.create_task(table_attributes)

        # assert
        args, _ = spark_job.call_args
        assert args[0] == "profiling"
        assert args[1].startswith("profiling-enrich-datahub")


def test_factory_maps_profiling_to_creator():
    assert TaskCreatorFactory.TASK_MAPPING[TaskEnum.PROFILING] is ProfilingTaskCreator
