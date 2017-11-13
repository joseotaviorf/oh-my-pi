import re
import sys
from collections import OrderedDict
from datetime import datetime

import requests
from dateutil.relativedelta import relativedelta
from qa_python_utils.default_logger import logger, _logger

from invoice import Invoice

args = sys.argv
full_date = datetime.strptime(args[2], '%Y-%m-%d %H:%M:%S') - relativedelta(months=1)
exec_year, exec_month = full_date.strftime('%Y'), full_date.strftime('%m')


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

    def __init__(self):
        super(Report, self).__init__(_type='reports', year=exec_year, month=exec_month)

    @logger
    def request_data(self, endpoint_complement):
        request_result = requests.get(
            url='{0}/{1}/{2}/{3}/all'.format(Invoice.SEUBARRIGA_INVOICE['endpoint'], endpoint_complement, self.year,
                                             self.month),
            headers={'jwt-token': Invoice.SEUBARRIGA_INVOICE['token']}
        )

        _logger.info('m=request_data, request_result={}'.format(request_result.content))
        return request_result.json()['file-url'], request_result.json()['status-url']

    @logger
    def prepare_and_transform_data(self):
        file_query = './db/2.datalake/queries/invoice/report_raw_transform.sql'
        with open(file_query) as f:
            q = f.read()

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
            ('from', str),
            ('to', str),
            ('description', str),
            ('amount', [float, re.compile(r'(\d+),(\d+)'), r'\g<1>.\g<2>']),
            ('item', str),
            ('year_month', str),
            ('due_date', [str, re.compile(Invoice.REGEX_DATE), Invoice.GROUP_DATE]),
            ('tenant_due_date', [str, re.compile(Invoice.REGEX_DATE), Invoice.GROUP_DATE]),
            ('tenant_paid_date', [str, re.compile(Invoice.REGEX_DATE), Invoice.GROUP_DATE]),
            ('tenant_status', [str, re.compile(Invoice.REGEX_DATE), Invoice.GROUP_DATE]),
            ('landlord_due_date', [str, re.compile(Invoice.REGEX_DATE), Invoice.GROUP_DATE]),
            ('landlord_paid_date', [str, re.compile(Invoice.REGEX_DATE), Invoice.GROUP_DATE]),
            ('landlord_status', str),
            ('delayed_days', int)
        ])

        self.transform_data(query=q.format(year=exec_year, month=exec_month), raw_columns=r_cols, clean_columns=c_cols,
                            clean_table_name='invoice')

    @logger
    def prepare_and_load_into_ods(self):
        file_query = './db/2.datalake/queries/invoice/report_clean_load_ods.sql'
        with open(file_query) as f:
            q = f.read()

        self.load_into_ods(query=q.format(year=exec_year, month=exec_month), ods_table='report')


if __name__ == '__main__':
    report = Report()

    if args[1] == 'extract':
        job_url, status_url = report.request_data(endpoint_complement='{}/invoice'.format(report._type))

        report.wait_for_results(status_url=status_url)

        content = report.request_job_data(job_url=job_url)
        data_frame = report.load_content_to_memory_as_csv(content=content)
        _object = report.convert_df_to_json(data_frame=data_frame)
        report.save_into_s3_raw(object=_object, file_path_prefix='raw/seubarriga/invoice/{}'.format(report._type),
                                raw_table_name='seubarriga_invoice')
        _object.flush()
    elif args[1] == 'transform':
        report.prepare_and_transform_data()
    elif args[1] == 'load':
        report.prepare_and_load_into_ods()
    else:
        _logger.info('m=__main__, msg=arg \'{}\' not recognized'.format(args[1]))
