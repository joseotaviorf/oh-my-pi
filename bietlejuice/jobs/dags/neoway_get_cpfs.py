# coding=utf-8
import cStringIO
import os
from datetime import datetime

import paramiko
from qa_python_utils.default_logger import _logger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.dags.util import environment as env

s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
NEOWAY_SFTP_PKEY = env.get_airflow_env_var('NEOWAY_SFTP_PKEY').replace('\\n', '\n')

MAIN_DAG_NAME = 'neoway-get-cpfs'
MAIN_START_DATE = datetime(2018, 7, 10)
MAIN_SCHEDULE_INTERVAL = '0 12 * * 2'  # At 12:00 on Tuesday.


def get_cpfs():
    _logger.info('m=get_cpfs, msg=connecting to sftp')
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    private_key = cStringIO.StringIO(NEOWAY_SFTP_PKEY)
    k = paramiko.RSAKey(file_obj=private_key)
    client.connect('files.neoway.com.br', username='quintoandarsftp', pkey=k)

    out_dir = '/files/saida/'
    backup_out_dir = '/files/backups/saida/'

    sftp = client.open_sftp()
    files = sftp.listdir(out_dir)
    _logger.info('m=get_cpfs, msg=found {} files: {}'.format(len(files), files))

    for f in files:
        if f.endswith('.csv'):
            _logger.info('m=get_cpfs, copying {} to s3'.format(f))
            with sftp.open(os.path.join(out_dir, f)) as fp:
                data_f = cStringIO.StringIO(fp.read())
            BaseETL.obj_to_s3(data_f, s3_bucket, 'raw/external/owners/enriched/{}'.format(f))

            _logger.info('m=get_cpfs, moving {} to backups'.format(f))
            sftp.rename(os.path.join(out_dir, f), os.path.join(backup_out_dir, f))

    sftp.close()

    _logger.info('m=get_cpfs, msg=done!')


# main dag
dag = BaseDAG.build_dag(
    dag_id=MAIN_DAG_NAME,
    start_date=MAIN_START_DATE,
    schedule_interval=env.convert_to_utc_schedule(MAIN_SCHEDULE_INTERVAL)
)

# operators
BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='neoway-get-cpfs',
    func_command=get_cpfs
)
