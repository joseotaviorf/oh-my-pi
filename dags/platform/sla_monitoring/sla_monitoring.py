from datetime import datetime, timedelta, timezone

from airflow.decorators import dag, task
from airflow.models import DagRun, Variable
from airflow.operators.python import get_current_context
from airflow.utils.session import provide_session
from airflow.utils.state import DagRunState

from bietlejuice.base.jiraops.jiraops_client import JiraOpsClient
from bietlejuice.services.configuration_service import ConfigurationService

DAG_NAME = "sla_monitoring"
DAG_ID = f"bietlejuice.{DAG_NAME}"


@task
def read_expected_times_from_config() -> dict:
    configuration_service = ConfigurationService(dag_name=DAG_NAME)
    return configuration_service.get_config("expected_times_to_finish")


@task
def identify_dags_that_should_have_finished(expected_times: dict) -> list:
    context = get_current_context()
    interval_start_time = context["data_interval_start"].time()
    interval_end_time = context["data_interval_end"].time()

    dags_that_should_have_finished = []
    for dag_id, expected_time_str in expected_times.items():
        expected_time = datetime.strptime(expected_time_str, "%H:%M").time()
        if interval_start_time <= expected_time <= interval_end_time:
            dags_that_should_have_finished.append(dag_id)

    return dags_that_should_have_finished


@task
def get_unfinished_dags(dag_id: str) -> str:
    """
    Returns the DAG ID if it has not finished successfully in the last 24 hours.
    """
    context = get_current_context()
    yesterday = context["data_interval_start"].date() - timedelta(days=1)

    if not has_successful_dag_runs_since_date(dag_id, yesterday):
        return dag_id
    else:
        return None


@provide_session
def has_successful_dag_runs_since_date(
    dag_id: str, date: datetime.date, session=None
) -> bool:
    filter = session.query(DagRun).filter(
        DagRun.dag_id == dag_id,
        DagRun.execution_date
        >= datetime(date.year, date.month, date.day, tzinfo=timezone.utc),
        DagRun.state == DagRunState.SUCCESS,
    )
    return session.query(filter.exists()).scalar()


@task
def notify_unfinished_dags(dag_ids: list, expected_times: dict) -> None:
    """
    Notify JiraOps about unfinished DAGs.
    """

    if not dag_ids:
        print("All DAGs have finished successfully.")
        return

    unfinished_dags = [dag_id for dag_id in dag_ids if dag_id is not None]
    print(f"Unfinished DAGs: {unfinished_dags}")

    message = "DAGs not finished by SLA"
    current_datetime = datetime.now()
    description = "The following DAGs have not finished by SLA:\n"
    for dag_id in unfinished_dags:
        description += f"- {dag_id} (Expected finish time: {expected_times[dag_id]})\n"
    description += f"Current time: {current_datetime.strftime('%Y-%m-%d %H:%M:%S %z')}."

    jiraops_credentials = Variable.get("JIRA_OPS_ONCALL_APIKEY")
    client = JiraOpsClient(jiraops_credentials)
    response = client.create_alert(
        message=message,
        description=description,
        tags=[DAG_ID],
    )

    try:
        response.raise_for_status()
        print("Alert created successfully.")
    except Exception as e:
        print(f"Failed to send request to JiraOps. Status code: {response.status_code}")
        print(f"Error message: {e}")


@dag(dag_id=DAG_ID, schedule="*/30 * * * *", start_date=datetime(2025, 4, 1))
def sla_monitoring():
    config_data = read_expected_times_from_config()
    dags_that_should_have_finished = identify_dags_that_should_have_finished(
        config_data
    )
    # .expand() is used to generate multiple tasks dynamically at runtime
    # each task will check a different DAG to find out if it has finished
    unfinished_dags = get_unfinished_dags.expand(dag_id=dags_that_should_have_finished)
    notify_unfinished_dags(unfinished_dags, config_data)


dag = sla_monitoring()
