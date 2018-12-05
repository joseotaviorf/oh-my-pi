# coding: utf-8

import json
import os
import tarfile
from datetime import datetime, timedelta
from io import BytesIO

import boto3
import kubernetes.client as kube
import sagemaker
from datetime import datetime
from qa_python_utils.aws.athena import AthenaClient
from airflow.models import DAG
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.dags.util import xcom

MAIN_DAG_NAME = 'skynet-listing_mgmt'
MAIN_START_DATE = datetime(2018, 3, 20)
MAIN_SCHEDULE_INTERVAL = '30 3 * * *'

RUN_LOCALLY = True
if RUN_LOCALLY:
    DATALAKE_BUCKET = '5a-datalake'
    OUTPUT_BUCKET = '5a-data-science'
    SKYNET_LISTMGMT_KWARGS = {}  # ?
    # {"params": 
    #     {"min_occurrence": 20, 
    #     "level": 2, 
    #     "embedding_sz": 64, 
    #     "learning_rate": 0.0001, 
    #     "batch_size": 1000, "epochs": 
    #     10, "to_shuffle": true, 
    #     "k": 10, 
    #     "window_sz": 3}, 
    # "week_span": 12, 
    # "image": "632540934959.dkr.ecr.us-east-1.amazonaws.com/quintoandar/skynet:recommender-master-latest", 
    # "deploy": 
    #     {"name": "recommender", 
    #     "namespace": "prod"}}
else:  # todo: how to generalize this code so that it also runs locally?
    DATALAKE_BUCKET = env.env.get_airflow_env_var('bi-datalake-s3-bucket')
    SKYNET_BUCKET = env.get_airflow_env_var('SKYNET_BUCKET')
    OUTPUT_BUCKET = env.env.get_airflow_env_var('bi-data-science-s3-bucket')
    SKYNET_LISTMGMT_KWARGS = env.get_airflow_env_var('SKYNET_LISTMGMT_KWARGS')
    SAGEMAKER_ROLE = env.get_airflow_env_var('SAGEMAKER_ROLE')
    SKYNET_KUBERNETES_TOKEN = env.get_airflow_env_var('SKYNET_KUBERNETES_TOKEN')
    KUBERNETES_API_ENDPOINT = env.get_airflow_env_var('KUBERNETES_API_ENDPOINT')

# output of fit # todo : for what?  we write there  the job_name/output/model.tar.gz ?
TRAINING_PATH = 'list_mgmt/training'
INPUT_PATH = 'list_mgmt/data/raw/dt={}'
PREDICTIONS_PATH = 'list_mgmt/data/predictions/dt={}'

logger = QuintoAndarLogger(MAIN_DAG_NAME)
athena = AthenaClient(DATALAKE_BUCKET)


@logger
def load_listing_info():
    """
    returns a dataframe with
    'sk_house_listing',
    'publication_date'
    """
    dirname = os.path.realpath('.')
    logger.info('Downloading the listing data per day of publication (indicators of interest, etc)')
    client = AthenaClient(DATALAKE_BUCKET)
    relative_path = 'bietlejuice/jobs/new_etl/listing_management/listing_information.sql'
    with open(os.path.join(dirname, relative_path), 'r') as fd:
        query = fd.read()
    lid = client.execute_query_and_wait_for_results(  # todo : no log of query
        query, s3_bucket=OUTPUT_BUCKET,
        bucket_folder_path='listing-mgmt/data/raw')
    return lid


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
    dirname = os.path.realpath('.')
    logger.info('Downloading the listing data per day of publication (indicators of interest, etc)')
    client = AthenaClient(DATALAKE_BUCKET)
    relative_path = 'bietlejuice/jobs/new_etl/listing_management/indicators_of_interest_by_date.sql'
    with open(os.path.join(dirname, relative_path), 'r') as fd:
        query = fd.read()
    hid = client.execute_query_and_wait_for_results(
        query, s3_bucket=OUTPUT_BUCKET,
        bucket_folder_path='listing-mgmt/data/raw')
    return hid


def build_raw_data(**kwargs):
    lid = load_listing_info()
    hid = load_historical_ioi()

    # todo : where is the key ti coming from?
    xcom.xcom_push(kwargs.get('ti'), key='lid', k_value=lid)
    xcom.xcom_push(kwargs.get('ti'), key='hid', k_value=hid)


def train_model(**kwargs):
    """gets the names of the datasets from the env variable
    and creates a sagemaker instance to 'train' the model (in our case,
    to make predictions)
    """

    lid = xcom.xcom_pull(kwargs.get('ti'), key='lid', dag_id=MAIN_DAG_NAME)
    hid = xcom.xcom_pull(kwargs.get('ti'), key='hid', dag_id=MAIN_DAG_NAME)
    # todo : what should be the value ? now?
    exec_date = kwargs.get('execution_date')

    params = kwargs.get('params')
    params.update(
        dict(raw_house_listing_file=lid + '.csv',
             raw_historical_data_file=hid + '.csv'))

    job_name = 'skynet-list_mgmt-' + datetime.now().strftime(
        "%Y-%m-%d-%H-%M-%S")
    logger.info(
        'm=train_model, job_name={}, params={}'.format(job_name, params))

    model = sagemaker.estimator.Estimator(
        image_name=kwargs.get('image'),  # todo : update
        role=SAGEMAKER_ROLE,
        train_instance_count=1,
        train_instance_type='ml.m5.2xlarge',  # todo : smaller. $0.538 per training hour
        output_path='s3://{}/{}'.format(SKYNET_BUCKET, TRAINING_PATH),
        hyperparameters=params)

    logger.info('m=train_model, starting training...')
    model.fit(
        's3://{}/{}'.format(
            SKYNET_BUCKET,
            INPUT_PATH.format(exec_date.strftime('%Y-%m-%d'))),
        job_name=job_name,
        logs=False)

    xcom.xcom_push(kwargs.get('ti'), key='job_name', k_value=job_name)


def untar_output(**kwargs):
    """untars the output of the training (in our case, the predictions)
    """

    bucket = boto3.resource('s3').Bucket(SKYNET_BUCKET)
    job_name = xcom.xcom_pull(
        kwargs.get('ti'), key='job_name', dag_id=MAIN_DAG_NAME)
    # todo: which exec date?
    exec_date = kwargs.get('execution_date')

    model_filename = os.path.join(
        TRAINING_PATH, job_name, 'output/model.tar.gz')
    model_obj = BytesIO(bucket.Object(model_filename).get()['Body'].read())

    logger.info('m=untar_output, msg=model loaded, decompressing output...')
    with tarfile.open(fileobj=model_obj) as tar:
        preds_json = tar.extractfile('preds.json').read()  # todo : currently files contain _date
        preds_csv = tar.extractfile('preds.csv').read()

    logger.info(
        'm=untar_output, msg=saving predictions to {}.'.format(
            PREDICTIONS_PATH.format(exec_date.strftime('%Y-%m-%d'))))
    preds_json_filename = os.path.join(
        PREDICTIONS_PATH.format(exec_date.strftime('%Y-%m-%d')),
        'preds.json')
    bucket.Object(preds_json_filename).put(Body=preds_json)
    preds_csv_filename = os.path.join(
        PREDICTIONS_PATH.format(exec_date.strftime('%Y-%m-%d')),
        'preds.json')
    bucket.Object(preds_csv_filename).put(Body=preds_csv)

    # todo : what are we doing here?
    athena.upsert_single_partition(
        bucket_folder_path=os.path.join(
            SKYNET_BUCKET, 'list_mgmt/predictions'),
        database='skynet',
        table='listing_mgmt_csv',
        partition_name='dt',
        partition_value=exec_date.strftime('%Y-%m-%d')
    )


def restart_service(**kwargs):
    """tell kubernetes to restart the service
     (it will reload the data from athena)
    """

    config = kube.Configuration()
    config.api_key['authorization'] = SKYNET_KUBERNETES_TOKEN
    config.api_key_prefix['authorization'] = 'Bearer'
    config.host = KUBERNETES_API_ENDPOINT
    config.verify_ssl = False

    api = kube.AppsV1Api(kube.ApiClient(config))
    name = kwargs.get('deploy', {}).get('name')
    namespace = kwargs.get('deploy', {}).get('namespace')
    now = datetime.now().strftime('%s')
    body = {
        "spec": {
            "template": {
                "metadata": {
                    "annotations": {
                        "reload": now
                    }
                }
            }
        }
    }

    r = api.patch_namespaced_deployment(name, namespace, body)

    logger.info('API response: {}'.format(r))


dag = DAG(
    dag_id=MAIN_DAG_NAME,
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

build_raw_data_op = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='build_raw_data',
    python_callable=build_raw_data,
    provide_context=True,  # todo means to give the kwargs ? 
    op_kwargs=json.loads(SKYNET_LISTMGMT_KWARGS)  # todo : what does it contain?
)

# calls the train function with the predict flag (on sagemaker)
train_model_op = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='train_model',
    provide_context=True,
    python_callable=train_model,
    execution_timeout=timedelta(hours=8),
    op_kwargs=json.loads(SKYNET_LISTMGMT_KWARGS)
)

# untars the files left by sagemaker in ..
untar_output_op = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='untar_output',
    provide_context=True,
    python_callable=untar_output,
    op_kwargs=json.loads(SKYNET_LISTMGMT_KWARGS)
)

# restarts the service in kubernetes
#  (so it will reload the files that we just untarred)
restart_service_op = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='restart_service',
    python_callable=restart_service,
    op_kwargs=json.loads(SKYNET_LISTMGMT_KWARGS)
)

build_raw_data_op >> train_model_op >> untar_output_op >> restart_service_op
# todo : where is the notify success operator ?
