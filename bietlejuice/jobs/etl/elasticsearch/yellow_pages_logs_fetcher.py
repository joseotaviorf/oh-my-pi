from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.elasticsearch import ESLogsFetcher

logger = QuintoAndarLogger('YellowPagesLogsFetcher')


class YellowPagesLogsFetcher(ESLogsFetcher):
    INDEX_NAME = 'fluentbit-kube-apps-{}'
    INDEX_DATE_FORMAT = '%Y.%m.%d'
    DOC_TYPE = 'flb_type'

    @logger
    def __init__(self, es_logs__hostname, logger_name):
        super(YellowPagesLogsFetcher, self).__init__(es_logs__hostname)
        self.logger_name = logger_name

    @logger
    def build_query(self, message_level):
        """
            Build a body query for elasticsearch api to match:
                app:"yellow_pages" AND
                env:"prod" AND
                message:"{message_level}:{logger_name}"
            ordered by timestamp.
        """
        message_q = '{}:{}'.format(message_level, self.logger_name)

        q = {
            "query": {
                "bool": {
                    "must": [
                        {
                            "match": {
                                "app": {
                                    "query": "yellow-pages",
                                    "minimum_should_match": "100%",
                                }
                            }
                        },
                        {"term": {"env": "prod"}},
                        {"match": {"message": message_q}},
                    ]
                }
            },
            "sort": [{"@timestamp": "asc"}],
        }

        self.body = q

        return self

    @logger
    def run(
        self,
        date_,
        message_level,
        step_size=1000,
        max_size=None,
        scroll=None
    ):
        # use date_ index
        self.index = self.INDEX_NAME.format(
            date_.strftime(self.INDEX_DATE_FORMAT))

        logs_paginator = (
            self
            .build_query(message_level=message_level)
            .fetch_all(step_size=step_size, max_size=max_size)
        )
        return logs_paginator
