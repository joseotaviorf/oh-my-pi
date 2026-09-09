"""
Hourly core-model loads for the Support Journey domain (Salesforce CDC).

Every ``load_core_support_journey_<table>`` task runs a Spark job from
``bietlejuice/base/sst/pipelines/core_model/support_journey/<table>.py`` that
follows the patterns defined by ``BaseCoreModelSparkJob``
(``bietlejuice.base.spark.base_core_model_spark_job``): standard CLI contract
(``parse_parameters`` <-> ``default_args``), table spec loaded from
``tables/<table>.yml``, SCD Type 2 versioning helpers, schema validation, and
Delta merge via ``DataFrameDeltaTableLoaderPipeline``. New tables should extend
that base class rather than introducing ad-hoc job structures.

Topology (mirrors ``salesforce_cdc``'s detached cluster lineages, on EMR):
each lineage — ``cases``, ``services`` and the shared ``general`` cluster for
every other table — has its own sensors, its own EMR job cluster and its own
previous-run gate, so one lineage lagging or failing never blocks the others.
Hour N+1 of a lineage starts only after its own hour N fully succeeded
(``wait_previous_lineage_*``: ``depends_on_past`` + ``wait_for_downstream``
against the lineage leaf ``end_cluster_*``). Unlike ``salesforce_cdc`` there
are NO per-lineage 1-slot Airflow pools: the ``emr_plugin`` operators default
to the global ``emr_api`` pool (EMR control-plane rate limit) and passing a
custom pool would silently replace it, so serialization here comes solely from
the gate flags.
"""

import os
from copy import deepcopy
from datetime import datetime, timedelta
from functools import partial
from pathlib import Path
from typing import Any, Dict, List, Tuple

import yaml
from airflow import DAG
from airflow.models.baseoperator import BaseOperator
from airflow.utils.task_group import TaskGroup

from bietlejuice.base.airflow.datasets.dataset_adder import DatasetAdder
from bietlejuice.base.airflow.job_cluster_engine import (
    attach_emr_job_cluster_finished_work_prerequisites,
    attach_emr_terminate_cluster_work_prerequisites,
    attach_job_cluster_engine_to_context,
    get_job_cluster_completion_sink,
)
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.notification.gchat_callback import GchatCallback
from bietlejuice.base.sst.airflow.common.common import parse_parameters
from bietlejuice.base.sst.airflow.operators.base import SStPlaceholderOperator
from bietlejuice.base.sst.airflow.operators.sensors import SStExternalTaskSensor
from bietlejuice.services.configuration_service import ConfigurationService

DAG_NAME = "core_support_journey"
DAG_ID = f"bietlejuice.{DAG_NAME.replace('.', '_')}"
ENV = os.environ.get("ENVIRONMENT")
CONFIG_SERVICE = ConfigurationService(DAG_NAME)
DATABRICKS_CONN_ID = "databricks_new"
BIETLEJUICE_REPO_PATH = CONFIG_SERVICE.get_config("databricks_bietlejuice_repo_path")
BASE_SPARK_JOB_PATH = f"{BIETLEJUICE_REPO_PATH}/spark_jobs/sst_pipelines/"
bucket = CONFIG_SERVICE.get_config("datalake_bucket")
CORE_SCHEMA = "core_support_journey"
DEFAULT_CLUSTER_ARGS = CONFIG_SERVICE.get_config("cluster")
LINEAGES_CONFIG: Dict[str, Dict[str, Any]] = CONFIG_SERVICE.get_config("lineages")
TABLES_DIR = Path(__file__).resolve().parent / "tables"

# Tables that get a dedicated cluster lineage (lineage name == table stem),
# mirroring salesforce_cdc's DEDICATED_CLUSTER_EVENTS. Every other table under
# ``tables/`` lands on the shared GENERAL_LINEAGE cluster.
DEDICATED_LINEAGE_TABLES = ("cases", "services")
GENERAL_LINEAGE = "general"

gchat_webhook_var = CONFIG_SERVICE.get_config("webhook_salesforce_cdc")
gchat_callback = GchatCallback(webhook_url_variable=gchat_webhook_var)


def list_table_specs_from_dir(tables_dir: Path) -> List[Tuple[str, Dict[str, Any]]]:
    """
    Load every ``*.yml`` in ``tables_dir`` and return (table_stem, spec_dict) sorted by stem.
    """
    if not tables_dir.is_dir():
        raise ValueError(f"Tables directory {tables_dir} does not exist")
    out: List[Tuple[str, Dict[str, Any]]] = []
    for path in sorted(tables_dir.glob("*.yml")):
        with open(path, encoding="utf-8") as handle:
            loaded = yaml.safe_load(handle) or {}
        out.append((path.stem, loaded))
    return out


def assign_tables_to_lineages(table_stems: List[str]) -> Dict[str, List[str]]:
    """
    Map each table stem to its cluster lineage, in stable build order:
    dedicated lineages first (declaration order), then the shared general
    lineage. Lineages without tables are dropped (e.g. general on forno if only
    dedicated tables exist), so ``execute-job-cluster[-N]`` local ids stay
    aligned with the lineages actually built.
    """
    assignments: Dict[str, List[str]] = {name: [] for name in DEDICATED_LINEAGE_TABLES}
    assignments[GENERAL_LINEAGE] = []
    for stem in table_stems:
        lineage = stem if stem in DEDICATED_LINEAGE_TABLES else GENERAL_LINEAGE
        assignments[lineage].append(stem)
    return {name: stems for name, stems in assignments.items() if stems}


def get_daily_target_logical_date(
    logical_date: datetime, execution_hour: int
) -> datetime:
    """
    Map this hourly DAG's ``logical_date`` to the daily upstream run's ``logical_date``.

    The upstream lands ``d-1``'s data at ``execution_hour`` UTC, so its logical_date
    sits at that hour. We point at the latest upstream run that has already completed:

        2026-06-23 03:00:00 -> 2026-06-22 03:00:00   (at/after the cutoff -> d-1)
        2026-06-23 02:00:00 -> 2026-06-21 03:00:00   (in the 00:00..cutoff gap -> d-2)
    """
    target = logical_date.replace(
        hour=execution_hour, minute=0, second=0, microsecond=0
    )

    # In the gap between midnight and ``execution_hour`` the d-1 upstream run has
    # not landed yet, so fall back one extra day.
    days_back = 2 if logical_date.hour < execution_hour else 1

    return target - timedelta(days=days_back)


BASE_PARAMETERS = {
    "env": ENV,
    "dag_name": DAG_NAME,
    "bucket": bucket,
    "partition_date": "{{ data_interval_start | ds }}",
    "partition_hour": "{{ data_interval_start.strftime('%H') }}",
}

_DEFAULT_EXECUTION_TIMEOUT_HOURS = 2


def lineage_cluster_args(lineage_name: str) -> Dict[str, Any]:
    """
    Cluster args for one lineage: the lineage's own ``cluster:`` conf block when
    present, else the DAG-level ``cluster:`` default. Deep-copied because
    ConfigurationService hands out shared dict references, and each lineage
    injects its own ``cluster_name`` (the preset default ``dag_id_run_id`` would
    otherwise name the concurrent lineage clusters identically).
    """
    lineage_conf = LINEAGES_CONFIG.get(lineage_name) or {}
    cluster_args = deepcopy(lineage_conf.get("cluster") or DEFAULT_CLUSTER_ARGS)
    custom = cluster_args.setdefault("custom_configurations", {})
    custom.setdefault("cluster_name", f"{DAG_ID}_{{{{ run_id }}}}_{lineage_name}")
    return cluster_args


def build_dag_execution_context(
    dag: DAG, cluster_args: Dict[str, Any]
) -> DagExecutionContext:
    """
    One context (and therefore one EmrJobClusterEngine) per lineage: each engine
    resolves its own cluster config and tracks its own
    ``emr_active_create_cluster_task_id``, so a lineage's spark steps can never
    point at another lineage's cluster XCom regardless of build order.
    """
    context = DagExecutionContext(
        dag=dag,
        environment=ENV,
        bucket=bucket,
        base_spark_jobs_path=BASE_SPARK_JOB_PATH,
        dag_args={},
        workflow_args={},
        cluster_args=cluster_args,
        databricks_conn_id=DATABRICKS_CONN_ID,
    )
    attach_job_cluster_engine_to_context(context, CONFIG_SERVICE)
    return context


def create_execute_job_cluster_task(
    dag_execution_context: DagExecutionContext, local_id: int
) -> BaseOperator:
    return dag_execution_context.job_cluster_engine.create_execute_cluster_task(
        config_service=CONFIG_SERVICE,
        minimum_cluster_runtime_version=None,
        # Repo convention (base_query_delta_workflow): cluster 1 keeps the
        # unsuffixed ``execute-job-cluster`` id, so cases inherits the task
        # history of the previous single-cluster layout.
        execute_job_cluster_local_id=local_id if local_id > 1 else None,
    )


def table_config_relative_path(table_stem: str) -> str:
    """
    Path relative to the Astro DAG bundle prefix (``astronomer/dags/`` on artifacts S3).
    """
    dag_dir = Path(__file__).resolve().parent
    parts = dag_dir.parts
    dags_idx = parts.index("dags")
    dag_package_path = "/".join(parts[dags_idx + 1 :])
    return f"{dag_package_path}/tables/{table_stem}.yml"


def create_load_table_task(
    dag_execution_context: DagExecutionContext, table_stem: str
) -> BaseOperator:
    base_parameters = {
        **BASE_PARAMETERS,
        "target_schema": CORE_SCHEMA,
        "target_table": table_stem,
        "job_name": f"load_core_support_journey_{table_stem}",
        "table_config_relative_path": table_config_relative_path(table_stem),
    }
    base_parameters = parse_parameters(base_parameters)
    execution_timeout_hours = _DEFAULT_EXECUTION_TIMEOUT_HOURS
    return dag_execution_context.job_cluster_engine.create_spark_python_task(
        spark_job_path=(
            f"{BASE_SPARK_JOB_PATH}core_model/support_journey/{table_stem}.py"
        ),
        task_id=f"load_core_support_journey_{table_stem}",
        job_parameters=base_parameters,
        execution_timeout_hours=execution_timeout_hours,
    )


def build_lineage_sensors(lineage_name: str, sensor_specs: Dict[str, Any]) -> TaskGroup:
    """
    One SStExternalTaskSensor per (upstream DAG, upstream task) pair, grouped
    per lineage so a late upstream only holds back the lineage that reads it.
    """
    with TaskGroup(group_id=f"start_sensors_{lineage_name}") as sensors_group:
        for external_dag_id, config in sensor_specs.items():
            for task_id in config["tasks"]:
                execution_date_fn = (
                    partial(
                        get_daily_target_logical_date,
                        execution_hour=config["execution_hour"],
                    )
                    if config["is_daily"]
                    else None
                )
                SStExternalTaskSensor(
                    task_id=f"sensor_{external_dag_id.replace('.', '_')}_{task_id}",
                    external_dag_id=external_dag_id,
                    external_task_id=task_id,
                    execution_date_fn=execution_date_fn,
                )
    return sensors_group


def build_cluster_lineage(
    dag: DAG, lineage_name: str, table_stems: List[str], local_id: int
) -> None:
    """
    One detached lineage: gate >> sensors >> EMR cluster >> loads >> terminate,
    with ``end_cluster_<lineage>`` as the leaf the next hour's gate waits on.
    """
    lineage_conf = LINEAGES_CONFIG.get(lineage_name)
    if lineage_conf is None or "dependencies" not in lineage_conf:
        raise ValueError(
            f"Lineage '{lineage_name}' (tables: {table_stems}) has no "
            f"'lineages.{lineage_name}.dependencies' entry in the environment "
            "conf — every lineage must declare which upstream tasks it waits on"
        )

    dag_execution_context = build_dag_execution_context(
        dag, lineage_cluster_args(lineage_name)
    )

    wait_previous_lineage = SStPlaceholderOperator(
        task_id=f"wait_previous_lineage_{lineage_name}",
        depends_on_past=True,
        wait_for_downstream=True,
    )
    sensors_group = build_lineage_sensors(lineage_name, lineage_conf["dependencies"])
    execute_job_cluster = create_execute_job_cluster_task(
        dag_execution_context, local_id
    )
    # The engine does not expose wait_for_downstream; set it post-construction
    # (depends_on_past=True already comes from default_args) so hour N+1's
    # cluster refuses to provision until hour N's full lineage — including the
    # end_cluster_* leaf wired below — succeeded, even if the gate is cleared.
    execute_job_cluster.wait_for_downstream = True

    load_tasks = []
    for stem in table_stems:
        load_task = create_load_table_task(dag_execution_context, stem)
        # Emit a per-table dataset event so downstream DAGs (e.g. dw_support_journey)
        # can trigger on this DAG via dependencies.yaml.
        DatasetAdder.attach_dataset_to_task(load_task)
        load_tasks.append(load_task)

    end_cluster = SStPlaceholderOperator(
        task_id=f"end_cluster_{lineage_name}",
        # The gate serializes hours; depends_on_past on the leaf would only add
        # a redundant cross-run chain that deadlocks the lineage after a clear.
        depends_on_past=False,
    )

    cluster_completion_sink = get_job_cluster_completion_sink(
        dag_execution_context, execute_job_cluster, end_cluster, local_id
    )
    attach_emr_job_cluster_finished_work_prerequisites(
        dag_execution_context,
        job_cluster_finished_task=end_cluster,
        work_completion_tasks=load_tasks,
    )

    (
        wait_previous_lineage
        >> sensors_group
        >> execute_job_cluster
        >> load_tasks
        >> cluster_completion_sink
    )
    attach_emr_terminate_cluster_work_prerequisites(
        dag_execution_context,
        cluster_completion_sink,
        execute_job_cluster_task=execute_job_cluster,
        job_cluster_finished_task=end_cluster,
    )
    # Immediate downstream of the gate and execute includes the lineage leaf so
    # wait_for_downstream waits for the full hour, not only sensors/cluster start.
    wait_previous_lineage >> end_cluster
    execute_job_cluster >> end_cluster


_DEFAULT_ARGS = {
    "owner": "Data SS",
    "email_on_retry": False,
    "retries": 3,
    # Per-table SCD-2 ordering: a load task must not apply hour N+1 before its
    # own hour N merged. The lineage-level gate additionally serializes the
    # whole lineage across hours.
    "depends_on_past": True,
}

with DAG(
    dag_id=DAG_ID,
    default_args=_DEFAULT_ARGS,
    schedule_interval="0 * * * *",
    start_date=datetime(2026, 5, 1),
    catchup=True,
    tags=["core_model", "support_journey", "SST", "Salesforce", "SF"],
    # Independent cluster lineages (cases, services, general) must not block
    # each other across hours via a shared start/end. 24 open hours keeps the
    # healthy lineages moving if one lags up to a day; within a lineage the
    # wait_previous_lineage_* gate keeps hours strictly serial.
    max_active_runs=24,
    on_failure_callback=gchat_callback.dag_failure_alert,
) as dag:
    table_stems = [stem for stem, _spec in list_table_specs_from_dir(TABLES_DIR)]
    for lineage_local_id, (lineage_name, lineage_tables) in enumerate(
        assign_tables_to_lineages(table_stems).items(), start=1
    ):
        build_cluster_lineage(dag, lineage_name, lineage_tables, lineage_local_id)
