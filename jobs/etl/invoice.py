import gzip
import io
import logging
import os
import re
import sys
import time
from StringIO import StringIO
from collections import OrderedDict
from datetime import datetime

import dateutil.relativedelta
import pandas
import requests
from jobs.base.base_etl import BaseETL
from jobs.base.enum_db import EnumDb
from jobs.wrappers.athena.athena_wrapper import AthenaWrapper

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

args = sys.argv

full_date = datetime.strptime(args[2], '%Y-%m-%d %H:%M:%S') - dateutil.relativedelta.relativedelta(months=1)
exec_year, exec_month = full_date.strftime('%Y'), full_date.strftime('%m')

bucket_datalake = os.environ['bi-datalake-s3-bucket']
process_name = BaseETL.get_current_filename()
tmp_dir = '/tmp'


class Invoice(object):
    """columns:
            contract-id (raw) - contract_id (clean),
            version,
            blocked,
            from,
            to,
            description,
            amount,
            item,
            year-month (raw) - year_month (clean),
            due-date (raw) - due_date (clean)
    """

    def request_data(self):
        logger.info(
            'm=request_data, process_name={}, exec_year={}, exec_month={}'.format(process_name, exec_year, exec_month))

        request_result = requests.get(
            url='{0}/{1}/{2}/{3}/preview'.format(os.environ['seubarriga-reports-endpoint'], process_name, exec_year,
                                                 exec_month),
            headers={'jwt-token': os.environ['seubarriga-reports-token']}
        )

        logger.info('m=request_data, request_result={}'.format(request_result.content))

        return request_result.json()['file-url']

    def request_job_data(self, job_url):
        logger.info('m=request_job_data, job_url={}'.format(job_url))

        job_result = requests.get(
            url=job_url,
            headers={'jwt-token': os.environ['seubarriga-reports-token']}
        )

        return job_result.content.decode('utf-8')

    def load_content_to_memory_as_csv(self, content):
        logger.info('m=load_content_to_memory_as_csv')

        memory_content = StringIO(content)
        return pandas.read_csv(memory_content)

    def convert_csv_to_json(self, data_frame):
        logger.info('m=convert_csv_to_json')

        gz_body = io.BytesIO()
        with gzip.GzipFile(fileobj=gz_body, mode='w') as fp:
            for row in data_frame.iterrows():
                fp.write(row[1].to_json().encode('utf-8'))
                fp.write('\n')

        return gz_body

    def save_into_s3(self, object, file_path_prefix):
        logger.info('m=save_into_s3, file_path={0}/{1}.gz'.format(file_path_prefix, process_name))

        BaseETL.obj_to_s3(
            obj_io=object,
            bucket=bucket_datalake,
            file_path='{0}/{1}_{2}-{3}.gz'.format(file_path_prefix, process_name, exec_year, exec_month))

    def transform_data(self):
        logger.info('m=transform_data')
        query = """
                    select "contract-id", version, blocked, 
                    "from", "to", description, amount, item, "year-month", "due-date"
                    from datalake_raw.seubarriga_invoice
                    where "year-month" = '{0}{1}'
                """.format(exec_year, exec_month)
        athena_wrapper = AthenaWrapper(bucket_datalake)
        athena_wrapper.create_parquet(
            key='clean/seubarriga/{0}/{1}_{2}-{3}.parq'.format(process_name, process_name, exec_year, exec_month),
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
                ('due-date', str)
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
                ('due_date', [str, re.compile(r'(\d{2})/(\d{2})/(\d{4})'), r'\g<3>-\g<2>-\g<1>']),
            ]))

    def load_into_ODS(self):
        logger.info('m=load_into_ODS')

        athena_wrapper = AthenaWrapper(bucket_datalake)
        data_frame = athena_wrapper.execute_query_and_return_dataframe(
            """
                select contract_id, version, blocked, "from", "to", description, amount, item, year_month, due_date 
                from datalake_clean.invoice
                where year_month = '{0}{1}'
            """.format(exec_year, exec_month)
        )

        BaseETL.execute_command(
            command="delete from invoice where year_month = '{0}{1}';".format(exec_year, exec_month),
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
        job_url = invoice.request_data()
        logger.info('m=main, msg=waiting for results to be available')

        time.sleep(60)

        content = invoice.request_job_data(job_url=job_url)
        data_frame = invoice.load_content_to_memory_as_csv(content=content)
        object = invoice.convert_csv_to_json(data_frame=data_frame)
        invoice.save_into_s3(object=object, file_path_prefix='raw/seubarriga/{0}'.format(process_name))
        object.flush()

    if args[1] == 'transform':
        invoice.transform_data()

    if args[1] == 'load':
        invoice.load_into_ODS()
