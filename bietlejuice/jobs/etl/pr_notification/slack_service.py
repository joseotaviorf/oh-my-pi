from abc import abstractmethod

import requests
from qa_python_utils.default_logger import QuintoAndarLogger

logger = QuintoAndarLogger('SlackService')


class SlackService(object):

    def __init__(self, webhook_url):
        self.webhook_url = webhook_url

    @staticmethod
    @abstractmethod
    def build_slack_message(objects, message_title):
        raise NotImplementedError('m=build_slack_message, msg=method not implemented')

    @logger
    def send_notifications_to_slack(self, message):
        requests.post(
            url=self.webhook_url,
            json={'text': message}
        )
