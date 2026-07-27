import logging
from urllib.parse import quote

from airflow.configuration import conf
from airflow.models.taskinstance import TaskInstance
from airflow.models.taskinstancekey import TaskInstanceKey
from airflow.utils.db import provide_session

try:
    from airflow.models.baseoperatorlink import BaseOperatorLink
except ImportError:
    # Older Airflow: BaseOperatorLink lived in airflow.models.baseoperator.
    from airflow.models.baseoperator import BaseOperatorLink

AIRFLOW_URL = conf.get("webserver", "base_url")


class DatasetTriggerOperatorLink(BaseOperatorLink):
    """
    Provides a link to trigger a dataset event in the Bietlejuice DAG.
    This link is used to trigger a dataset event for the task that is being executed.
    The link will include the DAG ID, task ID, and run ID in the query parameters.
    It should be used only for cases where the task fails and the user needs to trigger
    a dataset event manually to unlock dependents.
    """

    name = "Trigger Dataset Event"

    @provide_session
    def get_link(self, operator, *, ti_key: TaskInstanceKey, session=None) -> str:
        try:
            ti = (
                session.query(TaskInstance)
                .filter_by(
                    dag_id=ti_key.dag_id,
                    task_id=ti_key.task_id,
                    run_id=ti_key.run_id,
                    map_index=ti_key.map_index,
                )
                .first()
            )
            if not ti:
                raise Exception(f"TaskInstance not found for {ti_key}")
            last_run_start_date = ti.xcom_pull(
                task_ids=ti.task_id,
                key="last_run_start_date",
                include_prior_dates=True,
            )
            is_first_run = (
                1
                if (
                    last_run_start_date is None
                    or ti.start_date.date() != last_run_start_date.date()
                )
                else 0
            )
            return f"{AIRFLOW_URL}/dags/bietlejuice.trigger_datasets/trigger?source_dag_id={quote(ti.dag_id)}&source_task_id={quote(ti.task_id)}&source_run_id={quote(ti.run_id)}&is_first_run_of_date={is_first_run}"
        except Exception as e:
            logging.error("Error building trigger link: %s", e, exc_info=True)
            return f"{AIRFLOW_URL}/dags/bietlejuice.trigger_datasets/trigger"
