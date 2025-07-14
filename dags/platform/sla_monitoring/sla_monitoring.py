from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.opsgenie.opsgenie_client import OpsgenieClient
from datetime import datetime, timedelta, timezone

from airflow.decorators import task, dag
from airflow.models import DagRun, Variable
from airflow.operators.python import get_current_context
from airflow.utils.session import provide_session
from airflow.utils.state import DagRunState

DAG_NAME = "sla_monitoring"
DAG_ID = f"bietlejuice.{DAG_NAME}"


@task
def read_expected_times_from_config() -> dict:
    configuration_service = ConfigurationService(dag_name=DAG_NAME)
    return configuration_service.get_config("expected_times_to_finish")

@task
def identify_dags_that_should_have_finished(expected_times: dict) -> list:
    context = get_current_context()
    interval_start_time = context['data_interval_start'].time()
    interval_end_time = context['data_interval_end'].time()

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
    yesterday = context['data_interval_start'].date() - timedelta(days=1)
    
    if not has_successful_dag_runs_since_date(dag_id, yesterday):
        return dag_id
    else:
        return None

@provide_session
def has_successful_dag_runs_since_date(dag_id: str, date: datetime.date, session=None) -> bool:
    filter = session.query(DagRun).filter(
        DagRun.dag_id == dag_id,
        DagRun.execution_date >= datetime(date.year, date.month, date.day, tzinfo=timezone.utc),
        DagRun.state == DagRunState.SUCCESS,
    )
    return session.query(filter.exists()).scalar()

@task
def notify_unfinished_dags(dag_ids: list, expected_times: dict) -> None:
    """
    Notify Opsgenie about unfinished DAGs.
    """

    if not dag_ids:
        print("All DAGs have finished successfully.")
        return
    
    unfinished_dags = [dag_id for dag_id in dag_ids if dag_id is not None]
    print(f"Unfinished DAGs: {unfinished_dags}")
    
    summary_message = f"DAGs not finished by SLA"
    current_datetime = datetime.now()
    full_description = f"The following DAGs have not finished by SLA:\n"
    for dag_id in unfinished_dags:
        full_description += f"- {dag_id} (Expected finish time: {expected_times[dag_id]})\n"
    full_description += f"Current time: {current_datetime.strftime('%Y-%m-%d %H:%M:%S %z')}."

    resource_name = f"labels {{workflow_name={DAG_ID}}}"

    opsgenie_api_key = Variable.get("OPSGENIE_TEST_APIKEY")
    client = OpsgenieClient(opsgenie_api_key, "googlestackdriver")
    response = client.create_incident(
        resource_name=resource_name,
        summary_message=summary_message,
        full_description=full_description,
        issue_summary=full_description,
        resource_labels={"workflow_name": DAG_ID},
    )

    if response.status_code == 200:
        print("The incident was created successfully.")
        print("Response JSON:", response.json())
    else:
        response.raise_for_status()


@dag(dag_id=DAG_ID, schedule="*/30 * * * *", start_date=datetime(2025, 4, 1))
def sla_monitoring():
    config_data = read_expected_times_from_config()
    dags_that_should_have_finished = identify_dags_that_should_have_finished(config_data)
    # .expand() is used to generate multiple tasks dynamically at runtime
    # each task will check a different DAG to find out if it has finished
    unfinished_dags = get_unfinished_dags.expand(dag_id=dags_that_should_have_finished)
    notify_unfinished_dags(unfinished_dags, config_data)

dag = sla_monitoring()
