# coding=utf-8
import cStringIO
import os
from datetime import datetime
from datetime import timedelta

import pandas as pd
import paramiko
import petl
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import _logger, logger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.dags import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.dags.util import environment as env

s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
NEOWAY_SFTP_PKEY = env.get_airflow_env_var('NEOWAY_SFTP_PKEY').replace('\\n', '\n')

MAIN_DAG_NAME = 'neoway-get-cpfs'
MAIN_START_DATE = datetime(2018, 7, 10)
MAIN_SCHEDULE_INTERVAL = '0 12 * * 2'  # At 12:00 on Tuesday.


@logger(exclude='df')
def treat_phones_df(df):
    df2 = df['phone_numbers'].str.split(';', expand=True)
    df2_rnm = df2.add_prefix('phone_')
    result = pd.concat([df.drop(['cpf', 'phone_numbers'], axis=1), df2_rnm], axis=1)
    return petl.fromdataframe(df=result)


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

    if not files:
        raise Exception('there are no files to retrieve.')

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


def treat_cpfs_after_return(**kwargs):
    file_name = '{}/{}.sql'.format(DATALAKE_QUERIES_DIR, 'crawled_cpfs')
    exec_date = str(datetime.date(kwargs['execution_date'] + timedelta(days=7)))
    s3_file_path_csv = 'clean/crawled/cpfs_csv'
    full_s3_file_path = 'clean/crawled/cpfs/dt={0}/{0}.parq'.format(exec_date)

    _logger.info("m=treat_cpfs_after_return, getting crawled_cpfs: {}".format(datetime.now()))
    athena_client = AthenaClient(s3_bucket=s3_bucket)
    df = athena_client.execute_file_query_and_return_dataframe(file_name, exec_date)

    df_table = treat_phones_df(df)
    BaseETL.to_s3(filename='{}.csv'.format(exec_date), data_table=df_table,
                  bucket_folder_path='{}/{}'.format(s3_bucket, s3_file_path_csv))

    _logger.info("m=treat_cpfs_after_return, sending df to s3 as parquet: {}".format(datetime.now()))
    athena_client.create_parquet_from_df(key=full_s3_file_path, df=df)


def add_partition_to_athena(**kwargs):
    exec_date = str(datetime.date(kwargs['execution_date'] + timedelta(days=7)))
    s3_file_path = 'clean/crawled/cpfs'

    athena_client = AthenaClient(s3_bucket=s3_bucket)
    _logger.info("m=treat_cpfs_after_return, creating athena partition: dt={}".format(exec_date))
    athena_client.upsert_single_partition(bucket_folder_path='{}/{}'.format(s3_bucket, s3_file_path),
                                          database='datalake_clean', table='crawled_cpfs', partition_name='dt',
                                          partition_value=exec_date)


# main dag
dag = BaseDAG.build_dag(
    dag_id=MAIN_DAG_NAME,
    start_date=MAIN_START_DATE,
    schedule_interval=env.convert_to_utc_schedule(MAIN_SCHEDULE_INTERVAL)
)

# operators
neoway_get_cpfs = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='neoway-get-cpfs',
    python_callable=get_cpfs
)

treat_data_to_callcenter = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='treat_data_to_callcenter',
    provide_context=True,
    python_callable=treat_cpfs_after_return
)

add_partition_to_athena = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='add_partition_to_athena',
    provide_context=True,
    python_callable=add_partition_to_athena
)

neoway_get_cpfs >> treat_data_to_callcenter >> add_partition_to_athena
