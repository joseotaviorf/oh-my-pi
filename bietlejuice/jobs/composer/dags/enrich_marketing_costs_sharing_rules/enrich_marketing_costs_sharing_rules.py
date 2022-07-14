import pendulum
import os
from datetime import datetime

from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

import airflow.utils.helpers as airflow_helpers

from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.base.airflow import BaseDAG, DAGOwnerEnum


def sync_metastore(table_name, table_task):

    slugged_table_name = table_name.replace("_", "-")

    sync_metastore_table_structure_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"sync-{slugged_table_name}-hive-metastore-structure",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOBS_PATH
                + "sync_metastore_tables_structure.py",
                "parameters": [
                    DATALAKE_BUCKET,
                    LayerEnum.ENRICH.value,
                    SOURCE,
                    "--table-name",
                    table_name,
                ],
            }
        },
    )

    sync_metastore_table_partitions_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"sync-{slugged_table_name}-hive-metastore-partitions",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOBS_PATH
                + "sync_metastore_tables_partitions.py",
                "parameters": [
                    DATALAKE_BUCKET,
                    LayerEnum.ENRICH.value,
                    SOURCE,
                    "--table-name",
                    table_name,
                ],
            }
        },
    )

    airflow_helpers.chain(
        table_task,
        sync_metastore_table_structure_task,
        sync_metastore_table_partitions_task,
        terminate_cluster_task,
    )


# TODO: rename the folder /queries/marketing_costs_sharing_rules to /queries/enrich_marketing_costs_sharing_rules
SOURCE = (
    "marketing_costs_sharing_rules"
)  # TODO: we do not have 'sources' in enrichment DAG, only context
CONTEXT = SOURCE
DAG_NAME = f"enrich_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

DATALAKE_BUCKET = Variable.get("datalake_bucket")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{DAG_NAME}/"
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_default_bucket")

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

CUSTOM_LIBRARIES = [
    {"jar": f"{ARTIFACTS_S3_BUCKET}/jars/RedshiftJDBC42-no-awssdk-1.2.12.1017.jar"}
]

local_tz = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=local_tz)

cost_types = ["online", "offline"]

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_GROWTH,
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
    libraries=CUSTOM_LIBRARIES,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

load_old_rules_table = QuintoAndarDatabricksSubmitRunOperator(
    task_id=f"load-old-sharing-rules-from-redshift-to-datalake",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": f"{SPARK_JOBS_PATH}load_old_sharing_rules.py",
            "parameters": [ENV, DATALAKE_BUCKET],
        }
    },
)

sync_metastore("old_sharing_rules", load_old_rules_table)

create_cluster_task >> load_old_rules_table >> terminate_cluster_task

for cost_type in cost_types:

    load_rule = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"load-{cost_type}-sharing-rules-to-datalake",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": f"{SPARK_JOBS_PATH}load_sharing_rules.py",
                "parameters": [ENV, DATALAKE_BUCKET, SOURCE, cost_type],
            }
        },
    )
    sync_metastore(cost_type, load_rule)
    create_cluster_task >> load_rule >> terminate_cluster_task
