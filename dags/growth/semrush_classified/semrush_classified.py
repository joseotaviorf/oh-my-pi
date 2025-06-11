import os
import re
from datetime import datetime
from pendulum import timezone

from airflow.models import DAG
from airflow.utils.helpers import cross_downstream
from airflow.operators.python_operator import ShortCircuitOperator
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)
from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.base.airflow.dag_builders.main_builder.short_circuit_functions.dag_run_date_validators import (
    DAGRunDateValidators,
)
from bietlejuice.base.opsgenie.opsgenie_callback import OpsgenieCallback

## fuction to fetch toggles
def get_toggle_param(dag_run, toggle_param_name):
    toggle_param = dag_run.conf.get(toggle_param_name) if dag_run.conf else None
    if toggle_param:
        return toggle_param
    return False

SOURCE = "semrush_classified"
DAG_ID = f"bietlejuice.{SOURCE}"
MAIN_START_DATE = datetime(2023, 4, 1, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "0 10 * * *"
CLUSTER_DESCRIPTION = "databricks_12_2_max_io-memory_cluster"

config_service = ConfigurationService(SOURCE)
partition_cols = config_service.get_config("clean_partition_cols")
tables = config_service.get_config("tables")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"

transient_spark_job_file = (
    f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/load_{SOURCE}_transient.py"
)
raw_spark_job_file = (
    f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/load_{SOURCE}_raw.py"
)

doc_md_chart_url = config_service.get_config("doc_md_chart_url")
cluster_configuration = config_service.get_config(CLUSTER_DESCRIPTION)
default_libraries = config_service.get_config("default_libraries")
cluster_configuration["data_security_mode"] = "SINGLE_USER"
cluster_configuration["single_user_name"] = "{{ var.value.databricks_single_user_name }}"
cluster_configuration["spark_conf"]["spark.databricks.sql.initial.catalog.namespace"] = "quintoandar_{{ var.value.environment }}"
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
ENV = os.environ.get("ENVIRONMENT")

opsgenie_callback = OpsgenieCallback()
## DAG
dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_GROWTH,
        "wait_for_downstream": False,
        "depends_on_past": False,
        "on_failure_callback": opsgenie_callback.task_failure_alert,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(SOURCE).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
    user_defined_macros={"get_toggle_param": get_toggle_param},
)

skip_run_task = ShortCircuitOperator(
    task_id=f"check-day-to-skip-execution",
    python_callable=DAGRunDateValidators.check_is_specific_day_of_month,
    op_args=["{{ macros.ds_add(ds, 1) }}", 1],
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(databricks_conn_id="databricks_new", dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_configuration,
    libraries=default_libraries,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(databricks_conn_id="databricks_new", dag=dag, task_id="terminate-cluster"
)

datalake_task_group = DatalakeTaskGroup(databricks_conn_id="databricks_new", dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=SOURCE,
    spark_jobs_path=base_spark_jobs_path,
    athena_query_result_location=athena_query_results_bucket,
)

# TODO: Refactor using the new DatalakeTaskGroup to decouple functions.
load_semrush_transient_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id=f"load-transient-{SOURCE}",
    pool="default_pool",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": transient_spark_job_file,
            "parameters": [ENV, datalake_bucket]
            + [
                SOURCE,
                "{{ data_interval_start | ds }}",
                "{{ get_toggle_param(dag_run, 'overwrite_enabled') }}",
                "{{ get_toggle_param(dag_run, 'overcosts_enabled') }}",
            ],
        }
    },
    do_output_xcom_push=False,
)

raw_task_group = datalake_task_group.build_raw_task_group_for_all_tables(
    source=SOURCE,
    target_database_base_name=SOURCE,
    extraction_spark_job_file=raw_spark_job_file,
    raw_spark_job_extra_args=[
        SOURCE,
        "{{ data_interval_start | ds }}",
    ],
    has_hive_sync=False,
)

for table_name in tables:

    domain = tables[table_name]

    clean_task_group = datalake_task_group.build_clean_task_group(
        source_database_base_name=SOURCE,
        target_database_base_name=SOURCE,
        table_name=table_name,
        is_incremental=True,
        has_create_external_table_task=False,
        partitions=partition_cols,
        extra_query_template_params={
            "domain": domain
        },
    )

    skip_run_task.set_downstream(create_cluster_task)

    create_cluster_task.set_downstream(load_semrush_transient_task)

    load_semrush_transient_task.set_downstream(DatalakeTaskGroup.first_tasks(raw_task_group))

    cross_downstream(
        DatalakeTaskGroup.last_tasks(raw_task_group),
        DatalakeTaskGroup.first_tasks(clean_task_group),
    )

    terminate_cluster_task.set_upstream(DatalakeTaskGroup.last_tasks(clean_task_group))

    # adding data quality tasks
    independent_tasks = DatalakeTaskGroup.independent_tasks(clean_task_group)

    if independent_tasks:
        terminate_cluster_task.set_upstream(independent_tasks)
