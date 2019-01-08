import decimal
import json

import pandas as pd
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB
from bietlejuice.jobs.new_etl import SOURCE_QUERIES_DIR
from qa_python_utils import QuintoAndarLogger

logger = QuintoAndarLogger('LeadsReprocessor')


def decimal_default(obj):
    if isinstance(obj, decimal.Decimal):
        return float(obj)
    raise TypeError


class LeadsReprocessor(object):
    def __init__(self, config_json):
        # Configuring
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
        df_ids = self.__get_lead_ids_from_query()
        leads = self.__get_lead_infos_from_ids(df_leads=df_ids)
        # treated_leads = self.__treat_leads(leads)
        treated_leads = ''
        return leads

    @logger(exclude='json_list')
    def send_leads(self, json_list, queue='CrawlerLeads'):
        BaseETL.publish_messages(
            messages=[json.dumps(row, default=decimal_default, ensure_ascii=False, encoding='utf-8') for row in
                      json_list],
            queue_name=queue
        )

    @logger(exclude=['config_dict', 'required_columns'])
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
        lead_ids = BaseETL.from_db_query(db_enum=EnumDB.QuintoAndar_ebdb, query=self.query)

        # Remove header
        del lead_ids[0]

        # Convert to df
        df_leads = pd.DataFrame({'id': lead_ids})
        return df_leads

    @logger(exclude='df_leads')
    def __get_lead_infos_from_ids(self, df_leads):
        # Treat columns
        list_columns = self.defaultColumns
        columns_comma_separated = ','.join(list_columns).encode('UTF8')

        # Treat where clause
        list_leads = [str(elem[0]) for elem in df_leads['id']]
        leads_comma_separated = ','.join(list_leads).encode('UTF8')

        base_query = BaseETL.get_query_from_file_name(
            '{}/ebdb/leads/get_leads_to_reprocess.sql'.format(SOURCE_QUERIES_DIR))

        leads = BaseETL.from_db_query(db_enum=EnumDB.QuintoAndar_ebdb,
                                      query=base_query.format(columns=columns_comma_separated,
                                                              where_clause=leads_comma_separated))

        return leads

    @logger
    def __treat_leads(self):
        raise NotImplementedError
