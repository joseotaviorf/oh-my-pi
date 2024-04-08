from datetime import timedelta
from multiprocessing.pool import ThreadPool
import re

from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
from databricks_plugin.hooks.databricks_hook import QuintoAndarDatabricksHook
from pendulum import datetime, timezone

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum

DAG_NAME = "databricks_jobs_deletion"
DAG_ID = f"bietlejuice.{DAG_NAME}"
MAIN_START_DATE = datetime(2023, 7, 15, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "0 20 * * *"

PROJECT_TO_JOB_NAME_REGEX_MAPPING = {"bietlejuice": "^bietlejuice-", "wonka": "^wonka-"}
JOBS_REMOVAL_TIMEDELTA = timedelta(days=21)


def delete_databricks_jobs(remove_before_timedelta: timedelta, job_name_regex: str):
    databricks_hook = QuintoAndarDatabricksHook(
        databricks_conn_id="databricks_job_cluster"
    )
    current_timestamp = datetime.now()
    jobs_list = databricks_hook.list_jobs()
    jobs_id_list = {
        job["job_id"]: job["settings"]["name"]
        for job in jobs_list
        if job["created_time"]
        <= current_timestamp.subtract_timedelta(remove_before_timedelta).timestamp()
        * 1000
        and re.search(job_name_regex, job["settings"]["name"])
    }
    databricks_hook.log.info(
        "Quantity of jobs filtered to be deleted: {}".format(len(jobs_id_list))
    )
    databricks_hook.log.info(
        "Jobs to be deleted:\n{}".format("\n".join(list(jobs_id_list.values())))
    )
    ThreadPool(processes=10).map(databricks_hook.delete_job, list(jobs_id_list.keys()))


dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_PLATFORM,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME),
)

previous_task = None
for project, job_name_regex in PROJECT_TO_JOB_NAME_REGEX_MAPPING.items():
    delete_jobs_task = PythonOperator(
        task_id=f"delete-{project}-databricks-jobs",
        dag=dag,
        python_callable=delete_databricks_jobs,
        op_kwargs={
            "remove_before_timedelta": JOBS_REMOVAL_TIMEDELTA,
            "job_name_regex": job_name_regex,
        },
    )
    # We're making them all sequential instead of parallel due to the Databricks API rate limit
    if previous_task:
        previous_task >> delete_jobs_task
    previous_task = delete_jobs_task
