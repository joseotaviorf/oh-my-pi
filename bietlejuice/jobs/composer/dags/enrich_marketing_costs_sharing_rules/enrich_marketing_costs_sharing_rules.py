import pendulum
from datetime import datetime

from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.dags.enrich_marketing_costs_sharing_rules.enrich_marketing_costs_sharing_rules_subdag import (
    SharingRulesSubDag,
)

SOURCE = "marketing_costs_sharing_rules"
DAG_NAME = f"enrich_{SOURCE}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = Variable.get("environment")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

DATALAKE_BUCKET = Variable.get("datalake_bucket")
S3_MARKETING_BUCKET = Variable.get("datalake_marketing_bucket")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{DAG_NAME}/"
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

local_tz = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "15 3 * * *"

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=DOC_MD_BASE_URL, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

cost_types = ["online", "offline"]


enrich_sub_dag_class = SharingRulesSubDag(
    dag_id=DAG_ID,
    env=ENV,
    datalake_bucket=DATALAKE_BUCKET,
    database_base_name=SOURCE,
    spark_job_paths=SPARK_JOBS_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
    start_date=MAIN_START_DATE,
)

for cost_type in cost_types:

    enrich_sub_dag = enrich_sub_dag_class.get_sub_dag_operator(
        dag=dag,
        sub_dag_name=f"load-{cost_type}-to-enrich",
        sub_dag_func=enrich_sub_dag_class.build_subdag,
        cost_type=cost_type,
    )

    create_cluster_task >> enrich_sub_dag >> terminate_cluster_task
