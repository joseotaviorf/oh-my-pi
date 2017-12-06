import logging

from airflow.models import Variable
from airflow.configuration import conf
from airflow.operators.python_operator import PythonOperator
from jobs.dags.util.pd_operator import PagerDutyIncidentOperator


class PythonPagerDutyOperator(PythonOperator):
    """
    A Python Operator that triggers Pager Duty incidents on failures.
    """

    def __init__(self, *args, **kwargs):
        super(PythonPagerDutyOperator, self).__init__(
            on_failure_callback=PythonPagerDutyOperator.on_failure_callback,
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
