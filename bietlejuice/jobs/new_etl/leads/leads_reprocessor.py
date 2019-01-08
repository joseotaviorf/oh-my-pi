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
        # Configuring required columns
        required_columns = ['query', 'defaultColumns', 'infosExtras']

        # Checks
        self.__check_config_json(config_json)
        config_dict = json.loads(config_json)
        self.__check_required_params(config_dict, required_columns)

        # Setting up
        # Optional
        self.sleep = config_dict['sleep'] if 'sleep' in config_dict else 10
        self.sleep = config_dict['batchSize'] if 'batchSize' in config_dict else 10
        self.sleep = config_dict['additionalColumns'] if 'additionalColumns' in config_dict else None
        # Required
        self.query = config_dict['query']
        self.defaultColumns = config_dict['defaultColumns']
        self.infosExtras = config_dict['infosExtras']

    @logger
    def get_leads(self):
        ids = self.__get_lead_ids_from_query()
        leads = self.__get_lead_infos_from_ids(ids)
        treated_leads = self.__process_leads(leads)

        return treated_leads

    @logger(exclude='json_list')
    def send_leads(self, json_list, queue='CrawlerLeads'):
        BaseETL.publish_messages(
            messages=[json.dumps(row, default=decimal_default, ensure_ascii=False, encoding='utf-8') for row in
                      json_list],
            queue_name=queue
        )

    @logger(exclude='config_json')
    def __check_required_params(self, config_dict, required_columns):
        for column in required_columns:
            if column not in config_dict:
                raise ValueError(
                    "m=__check_mandatory_params, column={}, msg=Required column not in config_json".format(column))

    @logger(exclude='config_json')
    def __check_config_json(self, config_json):
        if config_json is None:
            raise ValueError('m=__check_config_json, msg=Config_json param is required.')

    @logger
    def __get_lead_ids_from_query(self):
        raise NotImplementedError

    @logger
    def __get_lead_infos_from_ids(self):
        raise NotImplementedError

    @logger
    def __process_leads(self):
        raise NotImplementedError
