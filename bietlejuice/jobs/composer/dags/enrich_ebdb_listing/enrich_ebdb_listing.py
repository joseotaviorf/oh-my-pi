import os
from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import cross_downstream, chain

from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseTaskGroup
from bietlejuice.jobs.composer.base.pipeline.layer_enum import LayerEnum
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 7, 1, 0, 0, 0, tzinfo=LOCAL_TZ)

CONTEXT = "ebdb_listing"
DAG_NAME = f"enrich_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")
SPECTRUM_IAM_ROLE = Variable.get("spectrum_iam_role")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")

S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base"
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)

CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_enrich_ebdb_listing_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=DOC_MD_BASE_URL, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

datalake_task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=DATALAKE_BUCKET,
    relative_query_path=CONTEXT,
    spark_jobs_path=SPARK_JOBS_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
)

enrich_task_groups = datalake_task_group.build_task_group_from_sql_files(
    layer=LayerEnum.ENRICH,
    source_database_base_name=CONTEXT,
    target_database_base_name=CONTEXT,
)

house_listing_tasks = enrich_task_groups.pop("house_listing")
house_listing_status_tasks = enrich_task_groups.pop("house_listing_status")

dependent_first_tasks = list()
dependent_first_tasks.extend(BaseTaskGroup.first_tasks(house_listing_tasks))
dependent_first_tasks.extend(BaseTaskGroup.first_tasks(house_listing_status_tasks))

dependent_last_tasks = list()
dependent_last_tasks.extend(BaseTaskGroup.last_tasks(house_listing_tasks))
dependent_last_tasks.extend(BaseTaskGroup.last_tasks(house_listing_status_tasks))

house_status_version_order_tasks = enrich_task_groups.pop("house_status_version_order")
dependency_first_tasks = BaseTaskGroup.first_tasks(house_status_version_order_tasks)
dependency_last_tasks = BaseTaskGroup.last_tasks(house_status_version_order_tasks)

chain(create_cluster_task, dependency_first_tasks)
cross_downstream(dependency_last_tasks, dependent_first_tasks)
chain(dependent_last_tasks, terminate_cluster_task)

chain(create_cluster_task, BaseTaskGroup.all_first_tasks(enrich_task_groups))
chain(BaseTaskGroup.all_last_tasks(enrich_task_groups), terminate_cluster_task)
