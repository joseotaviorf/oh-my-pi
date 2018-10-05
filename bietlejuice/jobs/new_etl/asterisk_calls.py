import gzip
import io
import json
import sys

import boto3
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB

args = sys.argv

logger = QuintoAndarLogger('Asterisk')

process_name = BaseETL.get_current_filename()


class Asterisk(object):

    def __init__(self, run_time, bucket):
        self.sqs = boto3.client('sqs')
        self.bucket = bucket
        self.exec_time = run_time.strftime('%H-%M-%S')
        self.exec_date = run_time.strftime('%Y-%m-%d')

    def get_asterisk_data_from_sqs(self, queue_url):
        logger.info('m=get_survey_data_from_sqs, msg=reading data from sqs')
        data = []
        response = self.sqs.receive_message(QueueUrl=queue_url, MaxNumberOfMessages=10)
        while response.get('Messages'):
            for message in response['Messages']:
                msg = json.loads(message['Body'])
                if 'Message' in msg:
                    data.append(json.loads(msg['Message']))
                else:
                    data.append(msg)
            response = self.sqs.receive_message(QueueUrl=queue_url, MaxNumberOfMessages=10)
        logger.info('m=get_call_data_from_sqs, msg=returning data')
        return data

    def save_asterisk_data_to_s3(self, data, suffix):
        logger.info('m=save_asterisk_data_to_s3, msg=saving to s3')
        if len(data) > 0:
            filename = "raw/asterisk/{}/execution_date={}/{}_{}.json.gz" \
                .format(suffix, self.exec_date, suffix, self.exec_time)
            gz_body = io.BytesIO()
            with gzip.GzipFile(fileobj=gz_body, mode="w") as fp:
                for record in data:
                    fp.write(json.dumps(record).replace("'null'", 'null'))
                    fp.write('\n')
            BaseETL.obj_to_s3(gz_body, self.bucket, filename)
        else:
            logger.info('m=save_asterisk_data_to_s3, msg=no data to save')

    def save_asterisk_data_to_dw(self):
        logger.info('m=save_asterisk_data_to_dw, msg=saving to dw')
        athena = AthenaClient(self.bucket)
        file_name = './db/datalake/queries/vw_asterisk_calls.sql'

        data_frame = athena.execute_file_query_and_return_dataframe(file_name)

        BaseETL.execute_command(
            command="""truncate {};""".format(process_name),
            db_enum=EnumDB.BI_DW,
            encoding='utf-8',
            commit=True
        )

        BaseETL.dataframe_to_db(
            df=data_frame,
            enum_db=EnumDB.BI_DW,
            table_name=process_name,
            encoding='utf-8'
        )
        logger.info('m=save_asterisk_data_to_dw, msg=saved!')

    def delete_asterisk_messages(self, url):
        logger.info('m=delete_asterisk_messages, msg=purging queue')
        self.sqs.purge_queue(QueueUrl=url)
