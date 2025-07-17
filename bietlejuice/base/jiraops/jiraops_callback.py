import json
from datetime import datetime

from airflow.models import Variable

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.jiraops.jiraops_client import JiraOpsClient


logger = QuintoAndarLogger("JiraOpsCallback")


class JiraOpsCallback:
    """JiraOps Callback class to create alerts on JiraOps"""

    def task_failure_alert(self, context):
        task_instance = context.get("task_instance")
        dag_id = task_instance.dag_id
        task_id = task_instance.task_id
        dag_owner = str(task_instance.task.owner)

        if Variable.get("environment") != "prod":
            logger.info("Skipping alert creation, since the environment is not Prod.")
            return
        logger.info(f"DAG [{dag_id}]: Failed task {task_id}, creating alert...")

        jiraops_credentials = json.loads(Variable.get("JIRA_OPS_ONCALL_APIKEY"))

        message = f"DAG: {dag_id} - Task: {task_id}"

        current_datetime = datetime.now()
        description = f"DAG: {dag_id} - Task: {task_id} Failed at: {current_datetime.strftime('%Y-%m-%d %H:%M:%S %z')}".strip()
        extra_properties = {"DAG": dag_id, "Task": task_id, "DAGOwner": dag_owner}

        client = JiraOpsClient(jiraops_credentials)
        response = client.create_alert(
            message=message,
            description=description,
            tags=[dag_id, task_id, "task failed"],
            extra_properties=extra_properties,
        )

        try:
            response.raise_for_status()
            logger.info(f"Alert created successfully for {dag_id}:{task_id}")
        except Exception as e:
            logger.error(
                f"Failed to create alert for {dag_id}:{task_id}. Status code: {response.status_code}"
            )
            logger.error(f"Error message: {e}")
