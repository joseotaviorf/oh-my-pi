from datetime import datetime
import pendulum

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG

DAG_ID = "bietlejuice.tenant_booking_review"
ENV = Variable.get("environment")
DW_BUCKET = Variable.get("dw_bucket")
SPECTRUM_IAM_ROLE = Variable.get("spectrum_iam_role")

# s3 vars
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
# spark_jobs path
SPARK_JOBS_PATH = S3_PREFIX + "/spark_jobs/tenant_booking_review/"

# databricks config
LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)

# dag params
local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "30 2 * * *"
TABLE_NAME = "tenant_booking_review"

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
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

datalake_clean_to_dw_staging_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="datalake-clean-to-dw-staging",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "create_dw_table_in_datalake.py",
            "parameters": [TABLE_NAME, DW_BUCKET, "staging", ENV],
        }
    },
)

dw_staging_to_dw_public_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="dw-staging-to-dw-public",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "create_dw_table_in_datalake.py",
            "parameters": [TABLE_NAME, DW_BUCKET, "public", ENV],
        }
    },
)

dw_public_to_redshift_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="dw_public_to_redshift",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "load_dw_table_into_redshift.py",
            "parameters": [
                SPECTRUM_IAM_ROLE,
                f"dim_{TABLE_NAME}",
                DW_BUCKET,
                "public",
                ENV,
            ],
        }
    },
)

airflow_helpers.chain(
    create_cluster_task,
    datalake_clean_to_dw_staging_task,
    dw_staging_to_dw_public_task,
    dw_public_to_redshift_task,
    terminate_cluster_task,
)
