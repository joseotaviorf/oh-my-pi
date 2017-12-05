from airflow.models import BaseOperator
from airflow.utils.decorators import apply_defaults
from airflow.exceptions import AirflowException
import pypd
import json
import logging


class PagerDutyIncidentOperator(BaseOperator):
    """
    Creates PagerDuty Incidents.
    """

    @apply_defaults
    def __init__(self,
                 api_key='unset',
                 title='unset',
                 service_id='No service id has been set',
                 *args,
                 **kwargs):
        super(PagerDutyAPIOperator, self).__init__(*args, **kwargs)
        self.api_key = api_key
        self.title = title
        self.service = service

    def execute(self, **kwargs):
        """
        PagerDutyIncidentOperator calls will not fail even if the call is not 
        successful. It should not prevent a DAG from completing in success.
        """

        pypd.api_key = self.api_key

        try:
            pypd.Incident.create(data={
                'type': 'incident',
                'title': self.details,
                'service': {
                    'type': 'service_reference',
                    'id': service_id,
                },
            })
        except Exception as ex:
            msg = "PagerDuty API call failed ({})".format(ex)
            logging.error(msg)
            raise AirflowException(msg)
