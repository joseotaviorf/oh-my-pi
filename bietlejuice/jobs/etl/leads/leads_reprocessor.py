import decimal
import json
import time
from collections import OrderedDict

import pandas as pd
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB
from bietlejuice.jobs.etl import SOURCE_QUERIES_DIR
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
        self._check_config_json(config_json)
        config_dict = json.loads(config_json, object_pairs_hook=OrderedDict)
        self._check_required_params(config_dict, required_columns)

        # Setting up
        # Optional
        self.sleep = config_dict['sleep'] if 'sleep' in config_dict else 10
        self.batchSize = config_dict['batchSize'] if 'batchSize' in config_dict else 10
        self.additionalColumns = config_dict['additionalColumns'] if 'additionalColumns' in config_dict else None
        # Required
        self.query = config_dict['query']
        self.defaultColumns = config_dict['defaultColumns']
        self.infosExtras = config_dict['infosExtras']

    @logger
    def get_leads(self):
        df_leads = self._get_lead_ids_from_query()
        treated_leads = self._treat_leads(df_leads)
        return treated_leads

    @logger(exclude='json_list')
    def send_leads(self, json_list, queue='CrawlerLeads'):
        list_splited = list(self._split_into_chunks(json.loads(json_list), self.batchSize))

        for item in list_splited:
            logger.info('m=send_leads, batch_size={}, queue={}, msg=Sending Batch to queue'.format(str(len(item)),
                                                                                                   queue))
            BaseETL.publish_messages(
                messages=[json.dumps(row, default=decimal_default, ensure_ascii=False, encoding='utf-8') for row in
                          item],
                queue_name=queue
            )

            # breathe
            time.sleep(self.sleep)

    @logger(exclude=['config_dict', 'required_columns'])
    def _check_required_params(self, config_dict, required_columns):
        for column in required_columns:
            if column not in config_dict:
                raise ValueError(
                    "m=_check_required_params, column={}, msg=Required column not in config_json".format(column))

    @logger(exclude='config_json')
    def _check_config_json(self, config_json):
        if config_json is None:
            raise ValueError('m=_check_config_json, msg=Config_json param is required.')

    @logger
    def _get_lead_ids_from_query(self):
        # Treat columns
        columns_comma_separated = ', '.join(
            ['cast({0} as {1}) as {0}'.format(k, v) for k, v in self.defaultColumns.iteritems()])

        base_query = BaseETL.get_query_from_file_name(
            '{}/ebdb/leads/get_leads_to_reprocess.sql'.format(SOURCE_QUERIES_DIR))
        lead_ids = BaseETL.from_db_query(db_enum=EnumDB.QuintoAndar_ebdb,
                                         query=base_query.format(columns=columns_comma_separated,
                                                                 where_clause=self.query),
                                         encoding='UTF8')

        # Convert to df
        df_leads = pd.DataFrame.from_records(lead_ids[1:], columns=lead_ids[0])

        return df_leads

    @logger(exclude='df_leads')
    def _treat_leads(self, df_leads):
        if 'id' not in df_leads.columns:
            raise ValueError('m=_treat_leads, msg=Query must provide an id column.')

        df_to_be_treated = df_leads

        # Add infosExtras to Lead
        df_to_be_treated['infosExtras'] = (self.infosExtras +
                                           (' ' + df_to_be_treated['infosExtras'].astype(
                                               str) if 'infosExtras' in df_leads.columns else '') +
                                           '; id_origin_lead=' +
                                           df_to_be_treated['id'].astype(str)).str.strip()
        df_to_be_treated.drop(columns=['id'], inplace=True)

        # Change origin
        df_to_be_treated['origem'] = 'Reprocessado'

        json_leads = df_to_be_treated.to_json(orient='records', force_ascii=False)

        return json_leads

    @logger(exclude='list')
    def _split_into_chunks(self, list, chunk_size):
        for i in range(0, len(list), chunk_size):
            yield list[i:i + chunk_size]
#
#
# if __name__ == '__main__':
#     from bietlejuice.jobs.dags.util import environment as env
#
#     env.set_airflow_var_to_local_env('EBDB')
#     config_json = env.get_airflow_env_var('REPROCESS_LEADS_CONFIG_FILE')
#     lr = LeadsReprocessor(config_json=config_json)
#     json_leads = lr.get_leads()
#     lr.send_leads(json_list=json_leads)
