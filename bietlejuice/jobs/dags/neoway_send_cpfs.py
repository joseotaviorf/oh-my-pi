# coding=utf-8
import cStringIO
import json
from datetime import datetime

import paramiko
from qa_python_utils.default_logger import _logger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.crawlers.crawler_cpfs import CrawlerCPFs

s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
NEOWAY_SEND_CPFS_PARAMS = env.get_airflow_env_var('NEOWAY_SEND_CPFS_PARAMS')
NEOWAY_SFTP_PKEY = env.get_airflow_env_var('NEOWAY_SFTP_PKEY').replace('\\n', '\n')

MAIN_DAG_NAME = 'neoway-send-cpfs'
MAIN_START_DATE = datetime(2018, 7, 9)
MAIN_SCHEDULE_INTERVAL = '0 19 * * 1'


def send_cpfs(limit, new):
    crawler_cpfs = CrawlerCPFs(s3_bucket=s3_bucket, google_maps_api_key=None)
    cpfs = crawler_cpfs.get_new_cpfs(new=new, limit=limit)
    _logger.info('m=send_cpfs, msg=got {} cpfs.'.format(len(cpfs)))

    _logger.info('m=send_cpfs, msg=connecting to sftp')
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    private_key = cStringIO.StringIO(NEOWAY_SFTP_PKEY)
    k = paramiko.RSAKey(file_obj=private_key)
    client.connect('files.neoway.com.br', username='quintoandarsftp', pkey=k)

    _logger.info('m=send_cpfs, msg=saving file to sftp')
    cpfs_fl = cStringIO.StringIO()
    cpfs.to_csv(cpfs_fl, header=False, index=False)
    cpfs_fl.seek(0)

    sftp = client.open_sftp()
    sftp.putfo(cpfs_fl, '/files/entrada/cpfs-{}.txt'.format(datetime.today().strftime('%Y%m%d')))
    sftp.close()

    _logger.info('m=send_cpfs, msg=done!')


# main dag
dag = BaseDAG.build_dag(
    dag_id=MAIN_DAG_NAME,
    start_date=MAIN_START_DATE,
    schedule_interval=env.convert_to_utc_schedule(MAIN_SCHEDULE_INTERVAL)
)

# operators
BaseDAG.get_quintoandar_python_operator(
    dag=dag,
    task_id='neoway-send-cpfs',
    func_command=send_cpfs,
    op_kwargs=json.loads(NEOWAY_SEND_CPFS_PARAMS)
)
