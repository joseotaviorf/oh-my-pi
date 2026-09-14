import sys
from unittest.mock import MagicMock

import pytest
from airflow.exceptions import DuplicateTaskIdFound
from airflow.models import DAG
from airflow.operators.empty import EmptyOperator

from bietlejuice.base.sst.airflow.common.emr_dag_kit import (
    build_dag_execution_context,
    create_execute_cluster_task,
    emr_execute_cluster_local_id,
    finalize_emr_pipeline,
)

# Airflow kwargs the fake EMR operators forward to BaseOperator; everything else
# (job_flow_id, steps, cluster_configuration, ...) is EMR-only and dropped so the
# fakes stay real Airflow tasks and the graph assertions below are meaningful.
_AIRFLOW_KWARGS = {
    "task_id",
    "dag",
    "pool",
    "retries",
    "retry_delay",
    "trigger_rule",
    "execution_timeout",
}


class _FakeEmrOperator(EmptyOperator):
    def __init__(self, **kwargs):
        super().__init__(**{k: v for k, v in kwargs.items() if k in _AIRFLOW_KWARGS})


class _FakeSubmitSteps(_FakeEmrOperator):
    @staticmethod
    def build_spark_submit_step(**_kwargs):
        return {
            "Name": "step",
            "ActionOnFailure": "CONTINUE",
            "HadoopJarStep": {"Jar": "command-runner.jar", "Args": []},
        }


@pytest.fixture(autouse=True)
def fake_emr_plugin():
    """Swap only the ``emr_plugin`` key in sys.modules.

    ``patch.dict(sys.modules, ...)`` snapshots and restores the whole dict, which
    evicts every module imported inside the block; re-importing
    ``airflow.models.connection`` then raises "Table 'connection' is already
    defined". Touching a single key avoids that.
    """
    fake = MagicMock()
    fake.QuintoAndarEmrCreateClusterOperator = _FakeEmrOperator
    fake.QuintoAndarEmrSubmitStepsOperator = _FakeSubmitSteps
    fake.QuintoAndarEmrTerminateClusterOperator = _FakeEmrOperator

    sentinel = object()
    original = sys.modules.get("emr_plugin", sentinel)
    sys.modules["emr_plugin"] = fake
    try:
        yield fake
    finally:
        if original is sentinel:
            sys.modules.pop("emr_plugin", None)
        else:
            sys.modules["emr_plugin"] = original


def _config_service():
    config = MagicMock()
    config._deep_update = lambda a, b: {**a, **(b or {})}
    config.get_config.side_effect = lambda key: {
        "emr_test_cluster": {"spark_version": "emr-7.12.0"},
    }[key]
    return config


def _build_context(dag):
    config = _config_service()
    return (
        build_dag_execution_context(
            dag=dag,
            env="forno",
            bucket="b",
            base_spark_job_path="s3://x/spark_jobs/",
            cluster_args={"type": "emr_test_cluster"},
            config_service=config,
        ),
        config,
    )


def _build_shard(ctx, config, shard_index, local_id_fn=emr_execute_cluster_local_id):
    """Mirror salesforce_for_sale's per-shard lineage: gate -> cluster -> steps -> end."""
    local_id = local_id_fn(shard_index)
    gate = EmptyOperator(task_id=f"wait_previous_lineage_{shard_index}")
    execute = create_execute_cluster_task(ctx, config, local_id)
    end = EmptyOperator(task_id=f"end_cdc_cluster_{shard_index}")

    steps = [
        ctx.job_cluster_engine.create_spark_python_task(
            spark_job_path="s3://x/job.py",
            task_id=f"load_shard{shard_index}_{n}",
            job_parameters=[],
            execution_timeout_hours=1,
            pool=f"lineage_{shard_index}",
        )
        for n in range(2)
    ]

    gate >> execute
    for step in steps:
        execute >> step >> end
    gate >> end
    finalize_emr_pipeline(ctx, execute, steps, end, local_id)
    return {"gate": gate, "execute": execute, "end": end, "steps": steps}


class TestEmrExecuteClusterLocalId:
    def test_shard_zero_is_none_and_one_is_skipped(self):
        """1 is skipped so the execute/terminate suffixes cannot disagree."""
        assert emr_execute_cluster_local_id(0) is None
        assert emr_execute_cluster_local_id(1) == 2
        assert emr_execute_cluster_local_id(2) == 3


class TestFinalizeEmrPipeline:
    def test_single_shard_wires_terminate_and_end(self):
        dag = DAG(dag_id="kit_single", schedule=None)
        with dag:
            ctx, config = _build_context(dag)
            shard = _build_shard(ctx, config, 0)

        dag.validate()
        terminate = dag.get_task("terminate-emr-cluster")
        assert shard["execute"].task_id == "execute-job-cluster"
        # Every work task must gate BOTH terminate and end, not just the leaves.
        for step in shard["steps"]:
            assert terminate in step.downstream_list
            assert shard["end"] in step.downstream_list
        assert shard["end"] in terminate.downstream_list
        assert shard["end"].trigger_rule == "none_failed_min_one_success"

    def test_returns_terminate_sink(self):
        dag = DAG(dag_id="kit_sink", schedule=None)
        with dag:
            ctx, config = _build_context(dag)
            execute = create_execute_cluster_task(ctx, config, None)
            end = EmptyOperator(task_id="end")
            step = ctx.job_cluster_engine.create_spark_python_task(
                spark_job_path="s3://x/job.py",
                task_id="load_one",
                job_parameters=[],
                execution_timeout_hours=1,
            )
            execute >> step >> end
            sink = finalize_emr_pipeline(ctx, execute, [step], end, None)

        assert sink.task_id == "terminate-emr-cluster"

    def test_two_shards_do_not_collide(self):
        dag = DAG(dag_id="kit_two_shards", schedule=None)
        with dag:
            ctx, config = _build_context(dag)
            shards = [_build_shard(ctx, config, i) for i in range(2)]

        dag.validate()
        task_ids = {t.task_id for t in dag.tasks}
        assert {
            "execute-job-cluster",
            "terminate-emr-cluster",
            "execute-job-cluster-2",
            "terminate-emr-cluster-2",
        } <= task_ids

        first, second = (
            dag.get_task("terminate-emr-cluster"),
            dag.get_task("terminate-emr-cluster-2"),
        )
        upstream_first = {t.task_id for t in first.upstream_list}
        upstream_second = {t.task_id for t in second.upstream_list}
        assert upstream_first.isdisjoint(upstream_second)
        for shard, terminate in ((shards[0], first), (shards[1], second)):
            for step in shard["steps"]:
                assert terminate in step.downstream_list

    def test_naive_shard_index_would_collide(self):
        """Guards the reason emr_execute_cluster_local_id exists.

        Passing the raw 0-based index gives shard 1 ``execute-job-cluster-1`` but
        re-uses shard 0's ``terminate-emr-cluster``.
        """
        dag = DAG(dag_id="kit_naive", schedule=None)
        with pytest.raises(DuplicateTaskIdFound):
            with dag:
                ctx, config = _build_context(dag)
                for i in range(2):
                    _build_shard(ctx, config, i, local_id_fn=lambda idx: idx)

    def test_rejects_steps_built_against_another_cluster(self):
        """Creating both clusters before the steps would silently mis-target them."""
        dag = DAG(dag_id="kit_stale", schedule=None)
        with dag:
            ctx, config = _build_context(dag)
            first = create_execute_cluster_task(ctx, config, None)
            end = EmptyOperator(task_id="end")
            step = ctx.job_cluster_engine.create_spark_python_task(
                spark_job_path="s3://x/job.py",
                task_id="load_one",
                job_parameters=[],
                execution_timeout_hours=1,
            )
            first >> step >> end
            # Second cluster steals the engine's "active" cluster id.
            create_execute_cluster_task(ctx, config, 2)

            with pytest.raises(ValueError, match="different cluster task"):
                finalize_emr_pipeline(ctx, first, [step], end, None)
