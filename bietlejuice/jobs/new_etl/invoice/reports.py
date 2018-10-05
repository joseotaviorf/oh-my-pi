import re
from collections import OrderedDict

from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.new_etl import DATALAKE_QUERIES_DIR
from invoice import Invoice

logger = QuintoAndarLogger


class Report(Invoice):
    """columns:
    -----------------------------------------------------------------------------------
    |           raw               |          clean          |        ods              |
    |  table: seubarriga_invoice  |     table: invoice      |  table: invoice.report  |
    -----------------------------------------------------------------------------------
    |         contract-id         |       contract_id       |      contract_id        |
    |           version           |         version         |        version          |
    |           blocked           |         blocked         |        blocked          |
    |            from             |          from           |         from            |
    |             to              |           to            |          to             |
    |         description         |       description       |      description        |
    |           amount            |         amount          |        amount           |
    |            item             |          item           |         item            |
    |          year-month         |        year_month       |       ref_item_ym       |
    |          due-date           |         due_date        |        due_date         |
    |       tenant-due-date       |      tenant_due_date    |     tenant_due_date     |
    |      tenant-paid-date       |     tenant_paid_date    |    tenant_paid_date     |
    |        tenant-status        |       tenant_status     |      tenant_status      |
    |      landlord-due-date      |     landlord_due_date   |    landlord_due_date    |
    |      landlord-paid-date     |     landlord_paid_date  |    landlord_paid_date   |
    |       landlord-status       |      landlord_status    |     landlord_status     |
    |             -               |        delayed_days     |       delayed_days      |
    |             -               |            -            |        year_month       |
    -----------------------------------------------------------------------------------
    """

    def __init__(self, bucket, api_dict, execution_date):
        super(Report, self).__init__(
            bucket=bucket,
            _type='report',
            year=execution_date.strftime('%Y'),
            month=execution_date.strftime('%m'),
            api_dict=api_dict
        )

    @logger
    def request_data(self, endpoint_suffix):
        request_result = self._request_data('{}/{}/{}/all'.format(endpoint_suffix, self.year, self.month))

        logger.info('m=request_data, request_result={}'.format(request_result.content))
        return request_result.json()['file-url'], request_result.json()['status-url']

    @logger
    def transform_data(self):
        query = BaseETL.get_query_from_file_name('{}/invoice/report_raw_transform.sql'.format(DATALAKE_QUERIES_DIR))
        r_cols = OrderedDict([
            ('contract-id', str),
            ('version', str),
            ('blocked', str),
            ('from', str),
            ('to', str),
            ('description', str),
            ('amount', str),
            ('item', str),
            ('year-month', str),
            ('due-date', str),
            ('tenant-due-date', str),
            ('tenant-paid-date', str),
            ('tenant-status', str),
            ('landlord-due-date', str),
            ('landlord-paid-date', str),
            ('landlord-status', str),
            ('delayed_days', int)
        ])

        c_cols = OrderedDict([
            ('contract_id', long),
            ('version', str),
            ('blocked', bool),
            ('_from', str),
            ('_to', str),
            ('description', str),
            ('amount', [float, re.compile(Invoice.REGEX_MAPPING['float']['regex']),
                        Invoice.REGEX_MAPPING['float']['group']]),
            ('item', str),
            ('ref_item_ym', str),
            ('due_date', [str, re.compile(Invoice.REGEX_MAPPING['date']['regex']),
                          Invoice.REGEX_MAPPING['date']['group']]),
            ('tenant_due_date', [str, re.compile(Invoice.REGEX_MAPPING['date']['regex']),
                                 Invoice.REGEX_MAPPING['date']['group']]),
            ('tenant_paid_date', [str, re.compile(Invoice.REGEX_MAPPING['date']['regex']),
                                  Invoice.REGEX_MAPPING['date']['group']]),
            ('tenant_status', [str, re.compile(Invoice.REGEX_MAPPING['date']['regex']),
                               Invoice.REGEX_MAPPING['date']['group']]),
            ('landlord_due_date', [str, re.compile(Invoice.REGEX_MAPPING['date']['regex']),
                                   Invoice.REGEX_MAPPING['date']['group']]),
            ('landlord_paid_date', [str, re.compile(Invoice.REGEX_MAPPING['date']['regex']),
                                    Invoice.REGEX_MAPPING['date']['group']]),
            ('landlord_status', str),
            ('delayed_days', int)
        ])

        self._transform_data(
            query=query,
            raw_columns=r_cols,
            clean_columns=c_cols,
            clean_table_name='invoice'
        )
