import requests
from quintoandar_logger import QuintoAndarLogger
from airflow.models import Variable
from datetime import datetime

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
        current_unix_timestamp = datetime.timestamp(datetime.now())
        current_datetime = datetime.fromtimestamp(current_unix_timestamp)
        full_description = f"DAG: {dag_id} - Task: {task_id} Started At: {current_datetime.strftime('%Y-%m-%d %H:%M:%S %z')}. Prometheus: https://prometheus.apps.core-prd.habitat.zone/"
        url = f"https://api.opsgenie.com/v1/json/googlestackdriver?apiKey={opsgenie_api_key}"
        resource_name = f"labels {{workflow_name={dag_id}}}"
        issue_summary = f"""
                            Problem:  \n
                            Cause:  \n
                            Solution:  \n
                        """
        payload = {
            "incident": {
                "resource_name": resource_name,
                "state": "open",
                "started_at": current_unix_timestamp,
                "summary": summary_message,
                "description": full_description,
                "metric": {"labels": {"task_name": task_id, "state": "failed"}},
                "resource": {"labels": {"workflow_name": dag_id}},
            },
            "fields": {"summary": issue_summary},
            "version": 1.1,
        }

        headers = {"Content-Type": "application/json"}

        response = requests.post(url, json=payload, headers=headers)

        if response.status_code == 200:
            logger.info("The incident was created successfully.")
            logger.info("Response JSON:", response.json())
        else:
            logger.error(
                f"Failed to send request to Opsgenie. Status code: {response.status_code}"
            )
            logger.error("Error message:", response.text)
