import logging
import os
import sys
from base64 import b64decode
from datetime import datetime

from dateutil.relativedelta import relativedelta

here = os.path.dirname(os.path.realpath(__file__))
sys.path.append(os.path.join(here, 'vendor'))

import requests
import mysql.connector
import boto3

logging.basicConfig(level=logging.INFO)
_logger = logging.getLogger(__name__)


def failed_jobs(event, context):
    conn = connect_to_db()
    cursor = conn.cursor()
    failed_jobs = get_failed_jobs(cursor)
    if not failed_jobs:
        return

    _logger.info('m=airflow_failed_jobs, posting to slack')

    execution_date = (datetime.now() - relativedelta(days=1)).strftime('%Y-%m-%d')
    texts = '*Failed Jobs!* :white_frowning_face:\n'
    for index, failed_job in enumerate(failed_jobs):
        task_id = failed_job[0]
        dag_id = failed_job[1]
        url = 'http://capiroto.quintoandar.com.br/admin/airflow/graph?root=&dag_id={}'.format(dag_id)

        texts += '\n-- *{}* --\ntask_id: {}\ndag_id: {}\nexecution_date: {}\n<{}|go to airflow>\n'.format(index,
                                                                                                          task_id,
                                                                                                          dag_id,
                                                                                                          execution_date,
                                                                                                          url)

    response = requests.post(url='https://hooks.slack.com/services/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',
                             json={'text': texts})

    if response.status_code != 200:
        _logger.error('m=airflow_failed_jobs, response.status_code={}, response.content={}'.format(response.status_code,
                                                                                                   response.content))

    cursor.close()
    conn.close()


def connect_to_db():
    _logger.info('m=connect_to_db')

    db_host = decrypt_variable(os.environ['DB_HOST'])
    db_user = decrypt_variable(os.environ['DB_USER'])
    db_password = decrypt_variable(os.environ['DB_PASSWORD'])
    db_database = decrypt_variable(os.environ['DB_DATABASE'])
    db_port = decrypt_variable(os.environ['DB_PORT'])

    return mysql.connector.connect(host=db_host, user=db_user, password=db_password, database=db_database, port=db_port)


def get_failed_jobs(cursor):
    _logger.info('m=get_failed_jobs')
    cursor.execute(" select distinct task_id, dag_id "
                   "  from airflow.task_instance "
                   " where date(end_date) between subdate(curdate(), 1) and curdate() "
                   "  and dag_id like 'bi-%' "
                   "  and state = 'failed'")

    return cursor.fetchall()


def decrypt_variable(var):
    return boto3.client('kms').decrypt(CiphertextBlob=b64decode(var))['Plaintext']
