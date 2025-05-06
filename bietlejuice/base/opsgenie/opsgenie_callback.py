from quintoandar_logger import QuintoAndarLogger
from airflow.models import Variable
from datetime import datetime

from bietlejuice.base.opsgenie.opsgenie_client import OpsgenieClient

logger = QuintoAndarLogger("OpsgenieCallback")


class OpsgenieCallback:
    """Opsgenie Callback class to send alerts from airflow dags to Opsgenie"""

    def task_failure_alert(self, context):
        if Variable.get("environment") != "prod":
            logger.info(
                "Skip Incident creation, since the environment is not Production."
            )
            return
        logger.info("Task failed. Creating Opsgenie incident.")
        task_instance = context.get("task_instance")
        task_id = task_instance.task_id
        dag_id = task_instance.dag_id
        summary_message = f"DAG: {dag_id} - Task: {task_id}"
        opsgenie_api_key = Variable.get("OPSGENIE_ONCALL_APIKEY")
        current_datetime = datetime.now()
        full_description = f"DAG: {dag_id} - Task: {task_id} Started At: {current_datetime.strftime('%Y-%m-%d %H:%M:%S %z')}. Prometheus: https://prometheus.apps.core-prd.habitat.zone/"
        resource_name = f"labels {{workflow_name={dag_id}}}"
        issue_summary = f"""
                            Problem:  \n
                            Cause:  \n
                            Solution:  \n
                        """

        client = OpsgenieClient(opsgenie_api_key, "googlestackdriver")
        response = client.create_incident(
            resource_name=resource_name,
            summary_message=summary_message,
            full_description=full_description,
            metric_labels={"task_name": task_id, "state": "failed"},
            resource_labels={"workflow_name": dag_id},
            issue_summary=issue_summary,
        )

        if response.status_code == 200:
            logger.info("The incident was created successfully.")
            logger.info("Response JSON:", response.json())
        else:
            logger.error(
                f"Failed to send request to Opsgenie. Status code: {response.status_code}"
            )
            logger.error("Error message:", response.text)
