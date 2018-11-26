# coding: utf-8

import os
from datetime import datetime
from qa_python_utils.aws.athena import AthenaClient
from airflow.models import DAG
from airflow.operators import PythonOperator
from qa_python_utils import QuintoAndarLogger

MAIN_DAG_NAME = 'listing_time_to_rent'
MAIN_START_DATE = datetime(2018, 3, 20)
MAIN_SCHEDULE_INTERVAL = '30 3 * * *'

RUN_LOCALLY = True
if RUN_LOCALLY:
    bucket_datalake = '5a-datalake'  # for testing without airflow
    bucket_datascience = '5a-data-science'
    bucket_output = '5a-skynet'
else:  # todo: how to generalize this code so that it also runs locally?
    bucket_datalake = os.env.get_airflow_env_var('bi-datalake-s3-bucket')  # comment for testing without airflow
    bucket_datascience = os.env.get_airflow_env_var('bi-data-science-s3-bucket')
    bucket_output = os.env.get_airflow_env_var('SKYNET_BUCKET')

logger = QuintoAndarLogger('listing_mgmt')


@logger
def load_listing_info():
    """
    returns a dataframe with
    'sk_house_listing',
    'publication_date'
    """
    dirname = os.path.realpath('.')
    logger.info('Downloading the listing data per day of publication (indicators of interest, etc)')
    client = AthenaClient(bucket_datalake)
    relative_path = 'bietlejuice/jobs/new_etl/listing_management/listing_information.sql'
    with open(os.path.join(dirname, relative_path), 'r') as fd:
        query = fd.read()
    rid = client.execute_query_and_wait_for_results(  # todo : no log of query
        query, s3_bucket=bucket_datascience,
        bucket_folder_path='listing-mgmt/data/raw')
    return rid


@logger
def load_historical_ioi():
    """
    returns the name of the csv file on s3 containing a dataframe with,
     for each date, the number of events for each IOI
    #     u'cnt_listing_views', u'cnt_favorite_set',
    #     u'cnt_discarded', u'cnt_schedule_views', u'cnt_bookings', u'cnt_visits',
    #     u'cnt_offers', u'cnt_offers_accepted', u'cnt_docs_sent',
    #     u'cnt_docs_completed', u'cnt_docs_approved'

    we also include:
    'status_mod'
    'aluguel_mod'
    'iptu_mod'
    'condominio_mod'
    'last_status_day'
    """
    # todo : how to avoid cluttering the raw folder with new data every day?
    dirname = os.path.realpath('.')
    logger.info('Downloading the listing data per day of publication (indicators of interest, etc)')
    client = AthenaClient(bucket_datalake)
    relative_path = 'bietlejuice/jobs/new_etl/listing_management/indicators_of_interest_by_date.sql'
    with open(os.path.join(dirname, relative_path), 'r') as fd:
        query = fd.read()
    rid = client.execute_query_and_wait_for_results(
        query, s3_bucket=bucket_datascience,
        bucket_folder_path='listing-mgmt/data/raw')
    return rid


def store_results_in_s3():
    df_listing = load_listing_info()
    df_ioi = load_historical_ioi()


if __name__ == '__main__':
    store_results_in_s3()

dag = DAG(
    dag_id=MAIN_DAG_NAME,
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    max_active_runs=1,
    catchup=False
)

PythonOperator(
    dag=dag,
    task_id='store_results_in_s3',
    python_callable=store_results_in_s3
)

# add an operator to tell kube to create a new container on skynet with the
# preprocess/predict code and run train
# PythonOperator(
#     dag=dag,
#     task_id='train(preprocess&predict)',
#     python_callable=xxx
# )


# for future update (when api exists) : add a python operator to
# notify kubernetes to kill and restart the api container
# (the api then reloads the data in the athena database into memory)
# OR : just call serve on the existing container created in the previous
# operator
# PythonOperator(
#     dag=dag,
#     task_id='serve',
#     python_callable=serve
# )
