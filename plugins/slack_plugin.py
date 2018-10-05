from airflow.models import BaseOperator
from airflow.utils.decorators import apply_defaults
from airflow.exceptions import AirflowException
from airflow.plugins_manager import AirflowPlugin

import requests
import logging


class SlackOperator(BaseOperator):
    """
    Creates PagerDuty Incidents.
    """

    @apply_defaults
    def __init__(self,
                 webhook='unset',
                 channel='',
                 title='Message',
                 title_link='',
                 text='unset',
                 color='good',
                 *args,
                 **kwargs):
        super(SlackOperator, self).__init__(*args, **kwargs)
        self.webhook = webhook
        self.channel = channel
        self.title = title
        self.title_link = title_link
        self.text = text
        self.color = color

    def execute(self, **kwargs):
        data = {
            'channel':
            self.channel,
            'attachments': [{
                'title': self.title,
                'title_link': self.title_link,
                'color': self.color,
                'text': self.text
            }]
        }

        try:
            r = requests.post(self.webhook, json=data)
            r.raise_for_status()
            logging.info(r.text)
        except Exception as ex:
            msg = "Slack Webhook request failed ({})".format(ex)
            logging.error(msg)
            raise AirflowException(msg)


# Defining the plugin class
class SlackPlugin(AirflowPlugin):
    name = "slack"
    operators = [SlackOperator]
