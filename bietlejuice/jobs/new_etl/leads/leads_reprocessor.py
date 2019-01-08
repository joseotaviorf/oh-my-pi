import decimal
import json

from bietlejuice.jobs.base.base_etl import BaseETL
from qa_python_utils import QuintoAndarLogger

logger = QuintoAndarLogger('LeadsReprocessor')


def decimal_default(obj):
    if isinstance(obj, decimal.Decimal):
        return float(obj)
    raise TypeError


class LeadsReprocessor(object):
    def __init__(self, config_json):
        if config_json is None:
            raise ValueError('m=__init__, msg=config_json must be passed to class.')

        # Check

    @logger
    def get_leads(self):
        self.__process_leads()

    @logger
    def __process_leads(self):
        raise NotImplementedError

    @logger(exclude='json_list')
    def send_leads(self, json_list, queue='CrawlerLeads'):
        BaseETL.publish_messages(
            messages=[json.dumps(row, default=decimal_default, ensure_ascii=False, encoding='utf-8') for row in
                      json_list],
            queue_name=queue
        )
