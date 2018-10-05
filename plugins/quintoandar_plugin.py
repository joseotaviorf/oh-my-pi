from airflow.models import Variable
from airflow.plugins_manager import AirflowPlugin
from airflow.operators.python_operator import PythonOperator
from pagerduty_plugin import PagerDutyIncidentOperator
from slack_plugin import SlackOperator

import logging


class QuintoAndarPythonOperator(PythonOperator):
    """
    A Python Operator that triggers Pager Duty incidents on failures.
    """

    def __init__(self, *args, **kwargs):
        super(QuintoAndarPythonOperator, self).__init__(
            on_failure_callback=QuintoAndarPythonOperator.on_failure_callback,
            *args,
            **kwargs)

    @staticmethod
    def on_failure_callback(context):
        """
        Define the callback to trigger a Pager Duty incident on failure.
        :return: operator.execute
        """
        params = context['task_instance'].task.params

        try:
            api_key = params.get('pd_api_key') or Variable.get("pd_api_key")
            service_id = params.get(
                'pd_service_id') or Variable.get("pd_service_id")
        except KeyError as exc:
            logging.warning(
                "Variable not set, aborting creation of PagerDuty Incident: %s",
                str(exc))
            return

        operator = PagerDutyIncidentOperator(
            task_id=str(context['task_instance_key_str']),
            title=str(context['task_instance']),
            api_key=api_key,
            service_id=service_id,
            details='Host: {}'.format(context['conf'].get(
                'webserver', 'base_url')))

        return operator.execute(context=context)


class QuintoAndarSlackPythonOperator(PythonOperator):
    """
    A Python Operator that triggers Pager Duty incidents on failures.
    """

    def __init__(self, *args, **kwargs):
        super(QuintoAndarSlackPythonOperator, self).__init__(
            on_failure_callback=QuintoAndarSlackPythonOperator.
            on_failure_callback,
            *args,
            **kwargs)

    @staticmethod
    def on_failure_callback(context):
        """
        Define the callback to trigger a Pager Duty incident on failure.
        :return: operator.execute
        """
        params = context['task_instance'].task.params

        try:
            webhook = params.get(
                'slack_webhook') or Variable.get("slack_webhook")
            channel = params.get(
                'slack_channel') or Variable.get("slack_channel")
        except KeyError as exc:
            logging.warning("Variable not set, aborting Slack Webhook: %s",
                            str(exc))
            return

        operator = SlackOperator(
            task_id=str(context['task_instance_key_str']),
            webhook=webhook,
            channel=channel,
            color="danger",
            title="Airflow Task Failed",
            title_link=context['conf'].get('webserver', 'base_url'),
            text=str(context['task_instance']))

        return operator.execute(context=context)


# Defining the plugin class
class QuintoAndarPlugin(AirflowPlugin):
    name = "quintoandar"
    operators = [QuintoAndarPythonOperator, QuintoAndarSlackPythonOperator]
