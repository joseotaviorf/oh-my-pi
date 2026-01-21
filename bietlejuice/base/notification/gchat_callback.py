from datetime import datetime

from airflow.models import Variable

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.airflow.enums.dag_run_type_enum import DagRunTypeEnum
from bietlejuice.services.dataset_service import DatasetService
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message

logger = QuintoAndarLogger("GchatCallback")


class GchatCallback:
    """Google Chat Callback class to send notifications to a specific gchat space"""

    def __init__(self, webhook_url_variable: str = None, webhook_url: str = None):
        """
        Initialize the GchatCallback.

        Args:
            webhook_url_variable: Name of the Airflow Variable containing the webhook URL
            webhook_url: Direct webhook URL (takes precedence over webhook_url_variable)
        """
        self.webhook_url_variable = webhook_url_variable
        self.webhook_url = webhook_url

    def _get_webhook_url(self):
        """
        Get the webhook URL from either direct URL or Airflow Variable.
        This is called only when a message needs to be sent, not during DAG parsing.

        Returns:
            str: The webhook URL, or None if not available
        """
        if self.webhook_url:
            return self.webhook_url
        elif self.webhook_url_variable:
            try:
                return Variable.get(self.webhook_url_variable)
            except Exception as e:
                logger.error(
                    f"Failed to get webhook URL from variable {self.webhook_url_variable}: {e}"
                )
                return None
        else:
            logger.warning(
                "No webhook URL or variable provided. Notifications will be skipped."
            )
            return None

    def _send_message(self, context, status: str, include_task_id: bool = True):
        """
        Send a message to Google Chat when a task or DAG succeeds or fails.

        Args:
            context: Airflow context
            status: Status of the execution ("success" or "failure")
            include_task_id: If True, include task_id in messages
        """
        webhook_url = self._get_webhook_url()
        if not webhook_url:
            logger.warning("Webhook URL not configured. Skipping notification.")
            return

        task_instance = context.get("task_instance")
        dag_id = task_instance.dag_id
        dag_owner = str(task_instance.task.owner)
        task_id = task_instance.task_id if include_task_id else None
        environment = Variable.get("environment")
        run_type = DatasetService._get_run_type(context)

        logger.info(f"Run type: {run_type}, Environment: {environment}")

        # Only send notifications in prod and for non-test runs
        if environment == "prod" and run_type != DagRunTypeEnum.TEST_RUN:
            current_datetime = datetime.now()
            datetime_str = current_datetime.strftime("%Y-%m-%d %H:%M:%S %z")

            if include_task_id:
                message = f"*DAG: {dag_id}* - *Task: {task_id}*"
                status_emoji = "✅" if status == "success" else "❌"
                status_text = "SUCCEEDED" if status == "success" else "FAILED"
            else:
                message = f"*DAG: {dag_id}*"
                status_emoji = "✅" if status == "success" else "❌"
                status_text = "SUCCEEDED" if status == "success" else "FAILED"

            content = (
                f"{status_emoji} *{status_text}*\n\n"
                f"{message}\n"
                f"*Owner:* {dag_owner}\n"
                f"*Time:* {datetime_str}\n"
                f"*Environment:* {environment}\n"
                f"*Run Type:* {run_type.value}"
            )

            log_message = (
                f"DAG [{dag_id}]: Task {task_id} {status_text.lower()}, sending notification..."
                if include_task_id
                else f"DAG [{dag_id}]: {status_text.lower()}, sending notification..."
            )
            logger.info(log_message)

            gchat_message = Message(content=content, destination=webhook_url)
            success = GChatService.send_message(gchat_message)

            if success:
                success_message = (
                    f"Notification sent successfully for {dag_id}:{task_id}"
                    if include_task_id
                    else f"Notification sent successfully for {dag_id}"
                )
                logger.info(success_message)
            else:
                error_message = (
                    f"Failed to send notification for {dag_id}:{task_id}"
                    if include_task_id
                    else f"Failed to send notification for {dag_id}"
                )
                logger.error(error_message)
        else:
            logger.info(
                f"""
                    Skipping notification, since the environment is not Prod or the run type is TEST_RUN.
                    Run type: {run_type}, Environment: {environment}
                """
            )

    def task_success_alert(self, context):
        """Send a notification when a task succeeds."""
        self._send_message(context, status="success", include_task_id=True)

    def task_failure_alert(self, context):
        """Send a notification when a task fails."""
        self._send_message(context, status="failure", include_task_id=True)

    def dag_success_alert(self, context):
        """Send a notification when a DAG succeeds."""
        self._send_message(context, status="success", include_task_id=False)

    def dag_failure_alert(self, context):
        """Send a notification when a DAG fails."""
        self._send_message(context, status="failure", include_task_id=False)
