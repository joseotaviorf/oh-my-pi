import boto3
import json
import petl
import logging
import os
import sys
from datetime import datetime
from jobs.base.base_etl import BaseETL

args = sys.argv

logging.basicConfig(level=logging.INFO)
_logger = logging.getLogger(__name__)

execution_time = datetime.now()


class Asterisk(object):

    def __init__(self, run_time):
        self.sqs = boto3.client('sqs')
        self.suffix = run_time.strftime('%Y-%m-%d_%H-%M-%S')
        self.survey_queue_url = json.loads(os.environ['asterisk'])['survey_queue_url']
        self.survey_bucket_name = json.loads(os.environ['asterisk'])['survey_bucket_name']
        self.survey_columns = json.loads(os.environ['asterisk'])['survey_columns']

    def get_survey_data_from_sqs(self):
        _logger.info('m=get_survey_data_from_sqs, msg=reading data from sqs')
        data = []
        response = self.sqs.receive_message(QueueUrl=self.survey_queue_url, MaxNumberOfMessages=10)
        while response.get('Messages'):
            for message in response['Messages']:
                msg = json.loads(message['Body'])
                data.append(msg)
            response = self.sqs.receive_message(QueueUrl=self.survey_queue_url, MaxNumberOfMessages=10)
        _logger.info('m=get_survey_data_from_sqs, msg=returning data')
        return data

    def save_survey_data_to_s3(self, data):
        _logger.info('m=save_survey_data_to_s3, msg=saving to s3')
        df = petl.fromdicts(data, header=self.survey_columns)
        BaseETL.to_s3(
            'survey_{}.csv'.format(self.suffix),
            df,
            self.survey_bucket_name
        )

    def delete_survey_messages(self):
        _logger.info('m=delete_survey_messages, msg=purging queue')
        self.sqs.purge_queue(QueueUrl=self.survey_queue_url)

if __name__ == '__main__':
    asterisk = Asterisk(execution_time)
    if args[1] == 'survey':
        survey_data = asterisk.get_survey_data_from_sqs()
        asterisk.save_survey_data_to_s3(survey_data)
    elif args[1] == 'purge':
        asterisk.delete_survey_messages()
    else:
        _logger.info('m=__main__, msg=arg \'{}\' not recognized'.format(args[1]))