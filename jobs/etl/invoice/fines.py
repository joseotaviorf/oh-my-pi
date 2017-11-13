import re
import sys
from collections import OrderedDict
from datetime import datetime

import pandas as pd
import requests
from dateutil.relativedelta import relativedelta
from qa_python_utils.default_logger import logger, _logger

from invoice import Invoice

args = sys.argv
full_date = datetime.strptime(args[2], '%Y-%m-%d %H:%M:%S') - relativedelta(months=1)
exec_year, exec_month = full_date.strftime('%Y'), full_date.strftime('%m')


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

    def __init__(self):
        super(Fine, self).__init__(_type='fines', year=exec_year, month=exec_month)

    @logger
    def request_data(self, endpoint_complement):
        request_result = requests.get(
            url='{0}/{1}/{2}/{3}'.format(Invoice.SEUBARRIGA_INVOICE['endpoint'], endpoint_complement, self.year,
                                         self.month),
            headers={'jwt-token': Invoice.SEUBARRIGA_INVOICE['token']}
        )

        return request_result.content

    @logger
    def prepare_and_transform_data(self):
        file_query = './db/2.datalake/queries/invoice/fine_raw_transform.sql'
        with open(file_query) as f:
            q = f.read()

        r_cols = OrderedDict([
            ('contract-external-id', str),
            ('fine', str),
            ('due-date', str),
            ('paid-date', str)
        ])

        c_cols = OrderedDict([
            ('contract_id', long),
            ('fine', [float, re.compile(r'(\d+),(\d+)'), r'\g<1>.\g<2>']),
            ('due_date', [str, re.compile(Invoice.REGEX_DATE), Invoice.GROUP_DATE]),
            ('paid_date', [str, re.compile(Invoice.REGEX_DATE), Invoice.GROUP_DATE])
        ])

        self.transform_data(query=q.format(year=exec_year, month=exec_month), raw_columns=r_cols, clean_columns=c_cols,
                            clean_table_name='invoice_fine')

    @logger
    def prepare_and_load_into_ods(self):
        file_query = './db/2.datalake/queries/invoice/fine_clean_load_ods.sql'
        with open(file_query) as f:
            q = f.read()

        self.load_into_ods(query=q.format(year=exec_year, month=exec_month), ods_table='fine')


if __name__ == '__main__':
    fine = Fine()

    if args[1] == 'extract':
        result = fine.request_data(endpoint_complement='invoices/{}'.format(fine._type))
        data_frame = pd.read_json(result)
        _object = fine.convert_df_to_json(data_frame=data_frame)
        fine.save_into_s3_raw(object=_object, file_path_prefix='raw/seubarriga/invoice/{}'.format(fine._type),
                              raw_table_name='seubarriga_invoice_fine')
        _object.flush()
    elif args[1] == 'transform':
        fine.prepare_and_transform_data()
    elif args[1] == 'load':
        fine.prepare_and_load_into_ods()
    else:
        _logger.info('m=__main__, msg=arg \'{}\' not recognized'.format(args[1]))
