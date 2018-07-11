import re
from collections import OrderedDict

from qa_python_utils.default_logger import logger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.new_etl import DATALAKE_QUERIES_DIR
from invoice import Invoice


class Fine(Invoice):
    """columns:
    -----------------------------------------------------------------------------------
    |           raw                 |          clean          |        ods            |
    |table: seubarriga_invoice_fine |   table: invoice_fine   |  table: invoice.fine  |
    -----------------------------------------------------------------------------------
    |     contract-external-id      |       contract_id       |      contract_id      |
    |            fine               |           fine          |         fine          |
    |          due-date             |         due_date        |        due_date       |
    |         paid-date             |        paid_date        |    tenant_paid_date   |
    |             -                 |            -            |        year_month     |
    -----------------------------------------------------------------------------------
    """

    def __init__(self, bucket, api_dict, execution_date):
        super(Fine, self).__init__(
            bucket=bucket,
            _type='fine',
            year=execution_date.strftime('%Y'),
            month=execution_date.strftime('%m'),
            api_dict=api_dict
        )

    @logger
    def request_data(self, endpoint_suffix):
        request_result = self._request_data('{}/{}/{}'.format(endpoint_suffix, self.year, self.month))
        return request_result.content

    @logger
    def transform_data(self):
        query = BaseETL.get_query_from_file_name('{}/invoice/fine_raw_transform.sql'.format(DATALAKE_QUERIES_DIR))
        r_cols = OrderedDict([
            ('contract-external-id', str),
            ('fine', str),
            ('due-date', str),
            ('paid-date', str)
        ])

        c_cols = OrderedDict([
            ('contract_id', long),
            ('fine', [float, re.compile(Invoice.REGEX['float']), Invoice.GROUP['float']]),
            ('due_date', [str, re.compile(Invoice.REGEX['date']), Invoice.GROUP['date']]),
            ('paid_date', [str, re.compile(Invoice.REGEX['date']), Invoice.GROUP['date']])
        ])

        self._transform_data(
            query=query,
            raw_columns=r_cols,
            clean_columns=c_cols,
            clean_table_name='invoice_fine'
        )
