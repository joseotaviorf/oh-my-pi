import re
from collections import OrderedDict

from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.new_etl import DATALAKE_QUERIES_DIR
from invoice import SeuBarrigaInvoice

logger = QuintoAndarLogger('SeuBarrigaFine')


class SeuBarrigaFine(SeuBarrigaInvoice):
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

    def __init__(self, s3_bucket, api_dict, execution_date):
        super(SeuBarrigaFine, self).__init__(
            s3_bucket=s3_bucket,
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
        query = BaseETL.get_query_from_file_name(
            '{}/seu_barriga/invoice/fine_raw_transform.sql'.format(DATALAKE_QUERIES_DIR))
        r_cols = OrderedDict([
            ('contract-external-id', str),
            ('fine', str),
            ('due-date', str),
            ('paid-date', str)
        ])

        c_cols = OrderedDict([
            ('contract_id', str),
            ('fine', [str, re.compile(SeuBarrigaInvoice.REGEX_MAPPING['float']['regex']),
                      SeuBarrigaInvoice.REGEX_MAPPING['float']['group']]),
            ('due_date', [str, re.compile(SeuBarrigaInvoice.REGEX_MAPPING['date']['regex']),
                          SeuBarrigaInvoice.REGEX_MAPPING['date']['group']]),
            ('paid_date', [str, re.compile(SeuBarrigaInvoice.REGEX_MAPPING['date']['regex']),
                           SeuBarrigaInvoice.REGEX_MAPPING['date']['group']])
        ])

        self._transform_data(
            query=query,
            raw_columns=r_cols,
            clean_columns=c_cols,
            clean_table_name='seubarriga_invoice_fine'
        )
