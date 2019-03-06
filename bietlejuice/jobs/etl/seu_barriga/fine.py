from collections import OrderedDict

from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.etl.seu_barriga.invoice import SeuBarrigaInvoice

logger = QuintoAndarLogger('SeuBarrigaFine')


class SeuBarrigaFine(SeuBarrigaInvoice):
    """columns:
    ------------------------------------------------------------------------
    |           raw                   |                   clean            |
    | table: seu_barriga_invoice_fine |   table: seu_barriga_invoice_fine  |
    ------------------------------------------------------------------------
    |     contract-external-id        |               contract_id          |
    |            fine                 |                   fine             |
    |          due-date               |                 due_date           |
    |         paid-date               |                 paid_date          |
    ------------------------------------------------------------------------
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

        # TODO: add clean columns types after Spark migration
        _cols = OrderedDict([
            ('external_id_contract', str),
            ('fine', str),
            ('due_date', str),
            ('paid_date', str)
        ])

        self._transform_data(
            query=query,
            raw_columns=_cols,
            clean_columns=_cols,
            clean_table_name='seu_barriga_invoice_fine'
        )
