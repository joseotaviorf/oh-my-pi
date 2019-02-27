import json
import logging
from datetime import datetime
from bietlejuice.jobs.etl.elasticsearch import ESLogsFetcher
from qa_python_utils import QuintoAndarLogger

logger = QuintoAndarLogger('SkynetModelLogsFetcher')


class SkynetModelLogsFetcher(ESLogsFetcher):
    INDEX_NAME = 'fluentbit-kube-apps-{}'
    INDEX_DATE_FORMAT = '%Y.%m.%d'
    DOC_TYPE = 'flb_type'

    @logger
    def __init__(self, es_logs__hostname, app_logger_name):
        super(SkynetModelLogsFetcher, self).__init__(es_logs__hostname)
        self.app_logger_name = app_logger_name

    @logger
    def build_query(self, message_level):
        message_q = '{}:{}'.format(message_level, self.app_logger_name)

        q = {
            'query': {
                'bool': {
                    'must': [
                        {'match': {'app': 'skynet'}},
                        {'match': {'env': 'prod'}},
                        {'match': {'message': message_q}}
                    ]
                }
            }
        }

        self.body = q

        return self

    @logger
    def run(self, date_, message_level, step_size=1000, max_size=None):
        self.index = self.INDEX_NAME.format(
            date_.strftime(self.INDEX_DATE_FORMAT))

        logs = (self
                .build_query(message_level=message_level)
                .fetch_all(step_size=step_size, max_size=max_size))
        return logs


def sample():
    ES_LOGS__HOSTNAME = ('https://search-logs-wluvttx6dvl2pq6vgdhhwej7le' +
                         '.us-east-1.es.amazonaws.com/')
    EXECUTION_DATE = datetime(2019, 2, 26)
    APP_NAME = 'ClosingPredictor'

    es_extractor = SkynetModelLogsFetcher(
        es_logs__hostname=ES_LOGS__HOSTNAME,
        app_logger_name=APP_NAME
    )

    logs = es_extractor.run(
        date_=EXECUTION_DATE,
        message_level=logging.getLevelName(logging.INFO),
        step_size=10,
        max_size=25
    )
    logs = map(json.dumps, logs)

    with open('logs.out', 'w') as file:
        file.write('\n'.join(logs))


if __name__ == '__main__':
    sample()
