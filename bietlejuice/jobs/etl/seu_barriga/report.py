from collections import OrderedDict
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.etl.seu_barriga.invoice import SeuBarrigaInvoice

logger = QuintoAndarLogger('SeuBarrigaReport')


class SeuBarrigaReport(SeuBarrigaInvoice):
    """columns:
    ---------------------------------------------------------------------------
    |                raw                  |                clean              |
    |  table: seu_barriga_invoice_report  | table: seu_barriga_invoice_report |
    ---------------------------------------------------------------------------
    |         contract-id                 |            contract_id            |
    |           version                   |              version              |
    |           blocked                   |              blocked              |
    |            from                     |               from                |
    |             to                      |                to                 |
    |         description                 |            description            |
    |           amount                    |              amount               |
    |            item                     |               item                |
    |          year-month                 |             year_month            |
    |          due-date                   |              dt_due               |
    |       tenant-due-date               |           dt_tenant_due           |
    |      tenant-paid-date               |          dt_tenant_paid           |
    |        tenant-status                |            tenant_status          |
    |      landlord-due-date              |          dt_landlord_due          |
    |      landlord-paid-date             |          dt_landlord_paid         |
    |       landlord-status               |           landlord_status         |
    |              -                      |            days_delayed           |
    |           purpose                   |               purpose             |
    |    tenant_invoice_created_at        |        dt_tenant_invoice_created  |
    |    landlord_invoice_created_at      |       dt_landlord_invoice_created |
    ---------------------------------------------------------------------------
    """

    def __init__(self, s3_bucket, api_dict, execution_date):
        super(SeuBarrigaReport, self).__init__(
            s3_bucket=s3_bucket,
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
        query = BaseETL.get_query_from_file_name(
            '{}/seu_barriga/invoice/report_raw_transform.sql'.format(DATALAKE_QUERIES_DIR))

        # TODO: add clean columns types after Spark migration
        _cols = OrderedDict([
            ('id_contract', str),
            ('version', str),
            ('blocked', str),
            ('item_from', str),
            ('item_to', str),
            ('description', str),
            ('amount', str),
            ('item', str),
            ('ref_item_ym', str),
            ('dt_due', str),
            ('dt_tenant_due', str),
            ('dt_tenant_paid', str),
            ('tenant_status', str),
            ('dt_landlord_due', str),
            ('dt_landlord_paid', str),
            ('landlord_status', str),
            ('days_delayed', str),
            ('purpose', str),
            ('dt_tenant_invoice_created', str),
            ('dt_landlord_invoice_created', str)
        ])

        self._transform_data(
            query=query,
            raw_columns=_cols,
            clean_columns=_cols,
            clean_table_name='seu_barriga_invoice_report'
        )
