"""Helpers to wire a handwritten SST DAG onto an EMR job cluster.

The engine in ``bietlejuice.base.airflow.job_cluster_engine`` imposes a strict
call order that is easy to get wrong, and gets it wrong *silently*:

1. ``create_execute_cluster_task`` must run before any Spark step, because it
   sets ``ctx.emr_active_create_cluster_task_id`` and every step templates its
   ``job_flow_id`` off that task's XCom.
2. ``attach_emr_terminate_cluster_work_prerequisites`` must run **last**: it
   discovers the work tasks by walking the graph downstream of the create-cluster
   task, so any edge wired after it is invisible and the cluster is never
   terminated.

Hence the split: the caller creates the cluster, builds and wires its own steps,
then hands the leaves to :func:`finalize_emr_pipeline`.
"""

from typing import Any, Dict, List, Optional, Sequence

from airflow.models import DAG
from airflow.models.baseoperator import BaseOperator
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.airflow.job_cluster_engine import (
    attach_emr_job_cluster_finished_work_prerequisites,
    attach_emr_terminate_cluster_work_prerequisites,
    attach_job_cluster_engine_to_context,
    get_job_cluster_completion_sink,
)
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.services.configuration_service import ConfigurationService

logger = QuintoAndarLogger("sst.airflow.common.emr_dag_kit")


def build_dag_execution_context(
    dag: DAG,
    env: str,
    bucket: str,
    base_spark_job_path: str,
    cluster_args: Dict[str, Any],
    config_service: ConfigurationService,
) -> DagExecutionContext:
    """Build the context and attach the job cluster engine chosen by ``cluster_args["type"]``.

    An ``emr_*`` preset routes to ``EmrJobClusterEngine``; anything else falls back
    to Databricks. ``databricks_conn_id`` is picked up from ``cluster_args`` by
    ``DagExecutionContext.__post_init__`` when present, so it needs no parameter here.
    """
    context = DagExecutionContext(
        dag=dag,
        environment=env,
        bucket=bucket,
        base_spark_jobs_path=base_spark_job_path,
        dag_args={},
        workflow_args={},
        cluster_args=cluster_args,
    )
    attach_job_cluster_engine_to_context(context, config_service)
    return context


def emr_execute_cluster_local_id(shard_index: int) -> Optional[int]:
    """Map a 0-based shard index to the engine's ``execute_job_cluster_local_id``.

    The engine derives the two task ids from this value inconsistently:
    ``create_execute_cluster_task`` suffixes on a plain truthiness check, while
    ``get_job_cluster_completion_sink`` only suffixes when the value is ``> 1``.
    So a raw ``enumerate()`` collides -- shard 1 would get
    ``execute-job-cluster-1`` but re-use shard 0's ``terminate-emr-cluster``,
    raising ``DuplicateTaskIdFound`` at parse.

    Skipping ``1`` avoids that and keeps shard 0 on the canonical unsuffixed ids
    forever, so raising the shard count never renames shard 0's tasks (which
    would wedge a ``depends_on_past`` DAG under catchup).
    """
    return None if shard_index == 0 else shard_index + 1


def create_execute_cluster_task(
    dag_execution_context: DagExecutionContext,
    config_service: ConfigurationService,
    execute_job_cluster_local_id: Optional[int] = None,
) -> BaseOperator:
    """Create the cluster task. Must be called before this shard's Spark steps."""
    return dag_execution_context.job_cluster_engine.create_execute_cluster_task(
        config_service=config_service,
        minimum_cluster_runtime_version=None,
        execute_job_cluster_local_id=execute_job_cluster_local_id,
    )


def finalize_emr_pipeline(
    dag_execution_context: DagExecutionContext,
    execute_job_cluster: BaseOperator,
    work_completion_tasks: Sequence[BaseOperator],
    end_task: BaseOperator,
    execute_job_cluster_local_id: Optional[int] = None,
) -> BaseOperator:
    """Create the completion sink and wire the teardown. Call after every step edge exists.

    ``end_task`` is required, not optional: without it the engine looks for a task
    literally named ``job-cluster-finished``, and when that lookup fails it returns
    without wiring anything -- no terminate edges, no parse error, and a cluster
    that runs until autotermination.

    Returns the completion sink (``terminate-emr-cluster`` on EMR, ``end_task``
    on Databricks).
    """
    active_create_task_id = dag_execution_context.emr_active_create_cluster_task_id
    if (
        dag_execution_context.use_airflow_emr
        and active_create_task_id != execute_job_cluster.task_id
    ):
        # Steps template job_flow_id off whichever cluster was created last, so an
        # interleaved "create all clusters, then all steps" loop would silently pile
        # every step onto the last cluster.
        raise ValueError(
            "EMR steps were built against a different cluster task: "
            f"active create task is {active_create_task_id!r}, "
            f"finalizing {execute_job_cluster.task_id!r}. Create each shard's "
            "cluster and its steps together, before moving to the next shard."
        )

    cluster_completion_sink = get_job_cluster_completion_sink(
        dag_execution_context,
        execute_job_cluster,
        end_task,
        execute_job_cluster_local_id,
    )
    attach_emr_job_cluster_finished_work_prerequisites(
        dag_execution_context,
        job_cluster_finished_task=end_task,
        work_completion_tasks=list(work_completion_tasks),
    )
    for work_task in work_completion_tasks:
        work_task >> cluster_completion_sink
    # Last: this is the call that walks the graph to collect the work tasks.
    attach_emr_terminate_cluster_work_prerequisites(
        dag_execution_context,
        cluster_completion_sink,
        execute_job_cluster_task=execute_job_cluster,
        job_cluster_finished_task=end_task,
    )

    if (
        dag_execution_context.use_airflow_emr
        and cluster_completion_sink is not end_task
        and end_task not in cluster_completion_sink.downstream_list
    ):
        raise RuntimeError(
            f"{cluster_completion_sink.task_id} was not wired to {end_task.task_id}; "
            "the EMR cluster would never be terminated."
        )

    work_task_ids: List[str] = [task.task_id for task in work_completion_tasks]
    logger.info(
        f"m=finalize_emr_pipeline, msg=wired EMR teardown for dag "
        f"{dag_execution_context.dag.dag_id}: cluster={execute_job_cluster.task_id}, "
        f"sink={cluster_completion_sink.task_id}, end={end_task.task_id}, "
        f"work_completion_tasks={work_task_ids}"
    )
    return cluster_completion_sink
