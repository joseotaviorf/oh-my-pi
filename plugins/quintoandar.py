from airflow.models import Variable
from airflow.plugins_manager import AirflowPlugin
from airflow.operators.python_operator import PythonOperator
from plugins.pagerduty import PagerDutyIncidentOperator

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
        try:
            api_key = Variable.get("pd_api_key")
            service_id = Variable.get("pd_service_id")
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
            details='Host: {}'.format(
                context['conf'].get('webserver', 'base_url')))

        return operator.execute(context=context)


# Defining the plugin class
class QuintoAndarPlugin(AirflowPlugin):
    name = "quintoandar"
    operators = [QuintoAndarPythonOperator]
