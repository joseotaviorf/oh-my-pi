import boto3
import json
import logging
import os
import io
import gzip
import sys
from datetime import datetime
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDb
from qa_python_utils.aws.athena import AthenaClient

args = sys.argv

logging.basicConfig(level=logging.INFO)
_logger = logging.getLogger(__name__)

execution_time = datetime.now()

survey_queue_url = json.loads(os.environ['asterisk'])['survey_queue_url']
call_queue_url = json.loads(os.environ['asterisk'])['call_queue_url']
bucket = os.environ['bi-datalake-s3-bucket']
process_name = BaseETL.get_current_filename()


class Asterisk(object):

    def __init__(self, run_time):
        self.sqs = boto3.client('sqs')
        self.exec_time = run_time.strftime('%H-%M-%S')
        self.exec_date = run_time.strftime('%Y-%m-%d')

    def get_asterisk_data_from_sqs(self, queue_url):
        _logger.info('m=get_survey_data_from_sqs, msg=reading data from sqs')
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
        _logger.info('m=get_call_data_from_sqs, msg=returning data')
        return data

    def save_asterisk_data_to_s3(self, data, suffix):
        _logger.info('m=save_asterisk_data_to_s3, msg=saving to s3')
        if len(data) > 0:
            filename = "raw/asterisk/{}/execution_date={}/{}_{}.json.gz"\
                .format(suffix, self.exec_date, suffix, self.exec_time)
            gz_body = io.BytesIO()
            with gzip.GzipFile(fileobj=gz_body, mode="w") as fp:
                for record in data:
                    fp.write(json.dumps(record).replace("'null'", 'null'))
                    fp.write('\n')
            BaseETL.obj_to_s3(gz_body, bucket, filename)
        else:
            _logger.info('m=save_asterisk_data_to_s3, msg=no data to save')

    def save_asterisk_data_to_dw(self):
        _logger.info('m=save_asterisk_data_to_dw, msg=saving to dw')
        athena = AthenaClient(bucket)
        file_name = './bietlejuice/db/2.datalake/queries/vw_asterisk_calls.sql'

        data_frame = athena.execute_file_query_and_return_dataframe(file_name)

        BaseETL.execute_command(
            command="""truncate {};""".format(process_name),
            db_enum=EnumDb.BI_DW,
            encoding='utf-8',
            commit=True
        )

        BaseETL.dataframe_to_db(
            df=data_frame,
            enum_db=EnumDb.BI_DW,
            table_name=process_name,
            encoding='utf-8'
        )
        _logger.info('m=save_asterisk_data_to_dw, msg=saved!')

    def delete_asterisk_messages(self, url):
        _logger.info('m=delete_asterisk_messages, msg=purging queue')
        self.sqs.purge_queue(QueueUrl=url)

if __name__ == '__main__':
    asterisk = Asterisk(execution_time)
    if args[1] == 'survey':
        survey_data = asterisk.get_asterisk_data_from_sqs(survey_queue_url)
        asterisk.save_asterisk_data_to_s3(survey_data, 'survey')
    elif args[1] == 'calls':
        call_data = asterisk.get_asterisk_data_from_sqs(call_queue_url)
        asterisk.save_asterisk_data_to_s3(call_data, 'calls')
    elif args[1] == 'purge':
        asterisk.delete_asterisk_messages(survey_queue_url)
        asterisk.delete_asterisk_messages(call_queue_url)
    elif args[1] == 'dw':
        asterisk.save_asterisk_data_to_dw()
    else:
        _logger.info('m=__main__, msg=arg \'{}\' not recognized'.format(args[1]))