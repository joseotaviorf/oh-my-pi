from unittest.mock import MagicMock

import pytest

from bietlejuice.base.airflow.task_creators.execute_job_cluster_task_creator import (
    ExecuteJobClusterTaskCreator,
)


def test_create_task_delegates_to_job_cluster_engine():
    ctx = MagicMock()
    engine = MagicMock()
    op = MagicMock()
    engine.create_execute_cluster_task.return_value = op
    ctx.job_cluster_engine = engine
    config = MagicMock()

    creator = ExecuteJobClusterTaskCreator(
        dag_execution_context=ctx,
        config_service=config,
        minimum_cluster_runtime_version="12.2",
    )
    out = creator.create_task(execute_job_cluster_local_id=2)

    assert out is op
    engine.create_execute_cluster_task.assert_called_once_with(
        config_service=config,
        minimum_cluster_runtime_version="12.2",
        execute_job_cluster_local_id=2,
    )


def test_create_task_raises_when_engine_missing():
    ctx = MagicMock()
    ctx.job_cluster_engine = None
    creator = ExecuteJobClusterTaskCreator(
        dag_execution_context=ctx, config_service=MagicMock()
    )
    with pytest.raises(ValueError, match="job_cluster_engine"):
        creator.create_task()
