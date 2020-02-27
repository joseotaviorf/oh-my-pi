import json
import os
from collections import OrderedDict
from datetime import datetime

import pandas as pd
from airflow.models import DAG
from pymongo import MongoClient
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import QuintoAndarLogger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl import SOURCE_QUERIES_DIR

logger = QuintoAndarLogger('bi_crm_credit_real_time')

# global vars
MAIN_DAG_ID = 'bi-crm-credit-real-time'
MAIN_START_DATE = datetime(2019, 1, 1)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('*/3 * * * *')

# env vars
env.set_airflow_var_to_local_env('EBDB', 'DATA_ACC_AWS_ACCESS_KEY_ID', 'DATA_ACC_AWS_SECRET_ACCESS_KEY')
mongo_client_uri = env.get_airflow_env_var('MONGODB_CRM_URI')
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')


# functions
def send_newer_proposals_to_s3():
    send_data_to_s3(
        ebdb_filename='proposals_in_analysis',
        ustasks_filename='open_credit_tasks',
        sort_direction='asc'
    )


def send_older_proposals_to_s3():
    send_data_to_s3(
        ebdb_filename='proposals_in_analysis',
        ustasks_filename='open_credit_tasks',
        sort_direction='desc'
    )


@logger
def send_data_to_s3(ebdb_filename, ustasks_filename, sort_direction):
    file_path = '{}/ebdb/credit/{}.sql'.format(SOURCE_QUERIES_DIR, ebdb_filename)
    query = BaseETL.get_query_from_file_name(file_name=file_path)

    logger.info('m=send_data_to_s3, sql_filename={}, ustasks_filename={}, sort_direction={}, msg=querying EBDB'.format(
        ebdb_filename, ustasks_filename, sort_direction))
    proposal_result = BaseETL.from_db_query(
        db_enum=EnumDB.QuintoAndar_ebdb,
        query=query.format(sort_direction=sort_direction),
        encoding='utf8mb4'
    )
    proposal_df = pd.DataFrame(proposal_result[1:], columns=proposal_result[0])
    proposal_df['last_interaction'] = proposal_df['last_interaction'].astype(str)

    match_file_path = '{}/ustasks/credit/{}_match.json'.format(SOURCE_QUERIES_DIR, ustasks_filename)
    lookup_file_path = '{}/ustasks/credit/{}_lookup.json'.format(SOURCE_QUERIES_DIR, ustasks_filename)
    project_file_path = '{}/ustasks/credit/{}_project.json'.format(SOURCE_QUERIES_DIR, ustasks_filename)

    match_query_str = BaseETL.get_query_from_file_name(file_name=match_file_path) \
        .replace('__PROPOSAL_IDS__', str(proposal_df['id_proposal'].astype(str).to_list())) \
        .replace("'", '"')
    match_query = json.loads(match_query_str)

    lookup_query = json.loads(BaseETL.get_query_from_file_name(file_name=lookup_file_path))
    project_query = json.loads(BaseETL.get_query_from_file_name(file_name=project_file_path))

    complete_query = [match_query, lookup_query, project_query]

    assignees = []
    client = MongoClient(mongo_client_uri)
    db = client.tasks
    logger.info(
        'm=send_data_to_s3, sql_filename={}, ustasks_filename={}, sort_direction={}, msg=querying USTasks'.format(
            ebdb_filename, ustasks_filename, sort_direction))
    for row in db.tasks.aggregate(complete_query).batch_size(500):
        assignees.append(row)

    assignees_df = pd.DataFrame(assignees)
    assignees_df['origemId'] = assignees_df['origemId'].astype(int)
    assignees_df = assignees_df.sort_values(by='dataInicio', ascending=False).drop_duplicates(subset='origemId',
                                                                                              keep='first')

    logger.info(
        'm=send_data_to_s3, sql_filename={}, ustasks_filename={}, sort_direction={}, msg=merging EBDB with USTasks'.format(
            ebdb_filename, ustasks_filename, sort_direction))
    merged_df = pd.merge(proposal_df, assignees_df[['origemId', 'assigneeName']], how='left', left_on='id_proposal',
                         right_on='origemId')
    merged_df.drop('origemId', axis=1, inplace=True)
    merged_df.rename(columns={'assigneeName': 'analyst'}, inplace=True)

    # removing automatic assignment from proposal tasks
    merged_df.drop(merged_df[merged_df.analyst == 'Closing3 Time 3'].index, inplace=True)

    logger.info(
        'm=send_data_to_s3, sql_filename={}, ustasks_filename={}, sort_direction={}, msg=replacing nan values'.format(
            ebdb_filename, ustasks_filename, sort_direction))
    merged_df = merged_df.where((pd.notnull(merged_df)), '-')

    # removing already closed tasks/tasks with no Analyst
    merged_df.drop(merged_df[merged_df.analyst == '-'].index, inplace=True)

    key = 'clean/credit/proposals_in_analysis/{}.parq'.format(sort_direction)
    cols = OrderedDict([
        ('id_proposal', str),
        ('id_proponent', str),
        ('id_house', str),
        ('last_interaction', str),
        ('sort_direction', str),
        ('analyst', str)
    ])
    data_acc_aws_access_key_id = os.environ.get('DATA_ACC_AWS_ACCESS_KEY_ID')
    data_acc_aws_secret_access_key = os.environ.get('DATA_ACC_AWS_SECRET_ACCESS_KEY')
    athena_client = AthenaClient(s3_bucket, data_acc_aws_access_key_id, data_acc_aws_secret_access_key)
    athena_client.create_parquet_from_df(
        key=key,
        df=merged_df,
        raw_columns=cols,
        clean_columns=cols
    )


# dags
main_dag = DAG(
    dag_id=MAIN_DAG_ID,
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    max_active_runs=1,
    catchup=False
)

# operators
send_newer_proposals_to_s3_task = BaseDAG.build_python_operator(
    task_id='send_newer_proposals_to_s3',
    python_callable=send_newer_proposals_to_s3,
    dag=main_dag
)

send_older_proposals_to_s3_task = BaseDAG.build_python_operator(
    task_id='send_older_proposals_to_s3',
    python_callable=send_older_proposals_to_s3,
    dag=main_dag
)
