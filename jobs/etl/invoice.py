import gzip
import io
import json
import logging
import os
import re
import sys
import time
from StringIO import StringIO
from collections import OrderedDict
from datetime import datetime

import pandas
import requests
from dateutil.relativedelta import relativedelta
from jobs.base.base_etl import BaseETL
from jobs.base.enum_db import EnumDb
from qa_python_utils.aws.athena import AthenaClient

logging.basicConfig(level=logging.INFO)
_logger = logging.getLogger(__name__)

args = sys.argv

full_date = datetime.strptime(args[2], '%Y-%m-%d %H:%M:%S') - relativedelta(months=1)
exec_year, exec_month = full_date.strftime('%Y'), full_date.strftime('%m')

seubarriga_invoice = json.loads(os.environ['seubarriga'])['invoice']
bucket_datalake = os.environ['bi-datalake-s3-bucket']
process_name = BaseETL.get_current_filename()
tmp_dir = '/tmp'


class Invoice(object):
    """columns:
    --------------------------------------------
    |       raw          |       clean         |
    --------------------------------------------
    |    contract-id     |    contract_id      |
    |      version       |      version        |
    |      blocked       |      blocked        |
    |       from         |       from          |
    |        to          |        to           |
    |    description     |    description      |
    |      amount        |      amount         |
    |       item         |       item          |
    |     year-month     |     year_month      |
    |     due-date       |      due_date       |
    |  tenant-due-date   |   tenant_due_date   |
    | tenant-paid-date   |  tenant_paid_date   |
    |   tenant-status    |    tenant_status    |
    | landlord-due-date  |  landlord_due_date  |
    | landlord-paid-date |  landlord_paid_date |
    |  landlord-status   |   landlord_status   |
    --------------------------------------------
    """

    def __init__(self):
        self.athena_client = AthenaClient(bucket_datalake)

    def request_data(self):
        _logger.info(
            'm=request_data, process_name={}, exec_year={}, exec_month={}'.format(process_name, exec_year, exec_month))

        request_result = requests.get(
            url='{0}/{1}/{2}/{3}/preview'.format(seubarriga_invoice['reports-endpoint'], process_name, exec_year,
                                             exec_month),
            headers={'jwt-token': seubarriga_invoice['reports-token']}
        )

        _logger.info('m=request_data, request_result={}'.format(request_result.content))

        return request_result.json()['file-url'], request_result.json()['status-url']

    def is_job_finished(self, status_url):
        _logger.info('m=is_job_finished, status_url={}'.format(status_url))

        response = json.loads(self.__request_get(url=status_url))
        return 'process-running.status/success' in response['status']

    def request_job_data(self, job_url):
        _logger.info('m=request_job_data, job_url={}'.format(job_url))
        return self.__request_get(url=job_url)

    def __request_get(self, url):
        job_result = requests.get(
            url=url,
            headers={'jwt-token': seubarriga_invoice['reports-token']}
        )

        return job_result.content.decode('utf-8')

    def load_content_to_memory_as_csv(self, content):
        _logger.info('m=load_content_to_memory_as_csv')

        memory_content = StringIO(content)
        return pandas.read_csv(memory_content)

    def convert_csv_to_json(self, data_frame):
        _logger.info('m=convert_csv_to_json')

        gz_body = io.BytesIO()
        with gzip.GzipFile(fileobj=gz_body, mode='w') as fp:
            for row in data_frame.iterrows():
                fp.write(row[1].to_json().encode('utf-8'))
                fp.write('\n')

        return gz_body

    def save_into_s3(self, object, file_path_prefix):
        _logger.info(
            'm=save_into_s3, file_path={0}/ym={2}-{3}/{1}.gz'.format(file_path_prefix, process_name, exec_year,
                                                                     exec_month))

        BaseETL.obj_to_s3(
            obj_io=object,
            bucket=bucket_datalake,
            file_path='{0}/ym={2}-{3}/{1}.gz'.format(file_path_prefix, process_name, exec_year, exec_month)
        )

        self.athena_client.upsert_single_partition(
            bucket_folder_path='{}/raw/seubarriga/{}'.format(bucket_datalake, process_name),
            database='datalake_raw',
            table='seubarriga_{}'.format(process_name),
            partition_name='ym',
            partition_value='{}-{}'.format(exec_year, exec_month)
        )

    def transform_data(self):
        _logger.info('m=transform_data, msg=converting fields')
        query = """select "contract-id", version,
                    case
                      when lower(blocked) = 'true'
                        then 'True'
                      else 'False'
                    end as blocked,
                    "from", "to", description, amount, item, "year-month", "due-date", "tenant-due-date",
                    "tenant-paid-date", "tenant-status", "landlord-due-date", "landlord-paid-date", "landlord-status"
                    from datalake_raw.seubarriga_invoice
                    where ym = '{0}-{1}'""".format(exec_year, exec_month)

        regex_date = '(\d{2})/(\d{2})/(\d{4})'
        group_date = '\g<3>-\g<2>-\g<1>'
        key = 'clean/seubarriga/{0}/ym={2}-{3}/{1}.gz'.format(process_name, process_name, exec_year, exec_month)
        self.athena_client.create_parquet_from_query(
            key=key,
            query=query,
            raw_columns=OrderedDict([
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
                ('landlord-status', str)
            ]),
            clean_columns=OrderedDict([
                ('contract_id', long),
                ('version', str),
                ('blocked', bool),
                ('from', str),
                ('to', str),
                ('description', str),
                ('amount', [float, re.compile(r'(\d+),(\d+)'), r'\g<1>.\g<2>']),
                ('item', str),
                ('year_month', str),
                ('due_date', [str, re.compile(regex_date), group_date]),
                ('tenant_due_date', [str, re.compile(regex_date), group_date]),
                ('tenant_paid_date', [str, re.compile(regex_date), group_date]),
                ('tenant_status', [str, re.compile(regex_date), group_date]),
                ('landlord_due_date', [str, re.compile(regex_date), group_date]),
                ('landlord_paid_date', [str, re.compile(regex_date), group_date]),
                ('landlord_status', str)
            ]))

        self.athena_client.upsert_single_partition(
            bucket_folder_path='{}/clean/seubarriga/{}'.format(bucket_datalake, process_name),
            database='datalake_clean',
            table=process_name,
            partition_name='ym',
            partition_value='{}-{}'.format(exec_year, exec_month)
        )

        _logger.info('m=transform_data, msg=adding delay column')
        query = """with rent_delay as (
                      select *,
                       date_diff('day', cast(tenant_due_date as timestamp), 
                                 cast(tenant_paid_date as timestamp)) as rent_delayed_days
                       from datalake_clean.invoice 
                      where trim("from") = 'Inquilino'
                       and trim(item) = 'Aluguel'
                       and tenant_due_date is not null and tenant_paid_date is not null
                       and ym = '{0}-{1}'
                    )
                    select distinct 
                       inv.contract_id, inv.version, inv.blocked, inv."from", inv."to", inv.description,
                       inv.amount, inv.item, inv.year_month, inv.due_date, inv.tenant_due_date, inv.tenant_paid_date, 
                       inv.tenant_status, inv.landlord_due_date, inv.landlord_paid_date, inv.landlord_status,
                       cast(rd.rent_delayed_days as smallint) as delayed_days
                       from datalake_clean.invoice inv
                     left join rent_delay rd
                      on inv.contract_id = rd.contract_id
                       and inv.year_month = rd.year_month
                       and inv.item = rd.item
                       and inv.tenant_due_date is not null
                       and inv.tenant_paid_date is not null
                    where inv.ym = '{0}-{1}'""".format(exec_year, exec_month)

        self.athena_client.create_parquet_from_query(
            key=key,
            query=query,
            raw_columns=OrderedDict([
                ('contract_id', long),
                ('version', str),
                ('blocked', bool),
                ('from', str),
                ('to', str),
                ('description', str),
                ('amount', float),
                ('item', str),
                ('year_month', str),
                ('due_date', str),
                ('tenant_due_date', str),
                ('tenant_paid_date', str),
                ('tenant_status', str),
                ('landlord_due_date', str),
                ('landlord_paid_date', str),
                ('landlord_status', str),
                ('delayed_days', int)
            ])
        )

    def load_into_ODS(self):
        _logger.info('m=load_into_ODS')

        data_frame = self.athena_client.execute_query_and_return_dataframe(
            """select 
                  contract_id, version, blocked, "from", "to", description, amount, item, 
                  year_month, due_date, tenant_due_date, tenant_paid_date, tenant_status, 
                  landlord_due_date, landlord_paid_date, landlord_status, cast(delayed_days as smallint)
                from datalake_clean.invoice
                where ym = '{}-{}'""".format(exec_year, exec_month))

        BaseETL.execute_command(
            command="""delete from invoice where year_month = '{0}{1}';""".format(exec_year, exec_month),
            db_enum=EnumDb.BI_ODS,
            encoding='utf-8',
            commit=True
        )

        BaseETL.dataframe_to_ods(
            df=data_frame,
            table_name=process_name,
            encoding='utf-8'
        )


if __name__ == '__main__':
    invoice = Invoice()

    if args[1] == 'extract':
        job_url, status_url = invoice.request_data()

        _logger.info('m=main, msg=waiting for results to be available')
        while not invoice.is_job_finished(status_url=status_url):
            time.sleep(seubarriga_invoice['job-waiting-time'])

        content = invoice.request_job_data(job_url=job_url)
        data_frame = invoice.load_content_to_memory_as_csv(content=content)
        object = invoice.convert_csv_to_json(data_frame=data_frame)
        invoice.save_into_s3(object=object, file_path_prefix='raw/seubarriga/{0}'.format(process_name))
        object.flush()

    elif args[1] == 'transform':
        invoice.transform_data()

    elif args[1] == 'load':
        invoice.load_into_ODS()

    else:
        _logger.info('m=__main__, msg=arg \'{}\' not recognized'.format(args[1]))
