# coding: utf-8

import boto3
import json
import os
import tarfile
from datetime import datetime, timedelta
from io import BytesIO

import boto3
import kubernetes.client as kube
import sagemaker
import tarfile
from airflow.models import DAG
from datetime import datetime
from datetime import timedelta
from io import BytesIO
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags import SKYNET_QUERIES_DIR
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.dags.util import xcom

MAIN_DAG_NAME = 'skynet-listing-management'
MAIN_START_DATE = datetime(2018, 1, 1)
MAIN_SCHEDULE_INTERVAL = '30 6 * * *'

env.set_airflow_var_to_local_env(
    'AWS_SECRET_ACCESS_KEY', 'AWS_DEFAULT_REGION', 'AWS_ACCESS_KEY_ID',
    'AWS_REGION', 'AWS_ENDPOINT_URL')

DATALAKE_BUCKET = env.get_airflow_env_var('bi-datalake-s3-bucket')
SKYNET_BUCKET = env.get_airflow_env_var('SKYNET_BUCKET')
SKYNET_LISTMGMT_KWARGS = env.get_airflow_env_var('SKYNET_LISTMGMT_KWARGS')
SAGEMAKER_ROLE = env.get_airflow_env_var('SAGEMAKER_ROLE')
SKYNET_KUBERNETES_TOKEN = env.get_airflow_env_var('SKYNET_KUBERNETES_TOKEN')
KUBERNETES_API_ENDPOINT = env.get_airflow_env_var('KUBERNETES_API_ENDPOINT')

# where on s3 to write the input data to give to fit
# (and copy inside the container to /opt/ml/input/data/training)
INPUT_PATH = 'listing-mgmt/data/raw/dt={}'

# where to put the output of train on s3 (from /opt/ml/output in the container)
TRAINING_PATH = 'listing-mgmt/training'

# folder on s3 to untar the files found in TRAINING_PATH
PREDICTIONS_PATH = 'listing-mgmt/data/predictions/dt={}'

logger = QuintoAndarLogger(MAIN_DAG_NAME)
athena = AthenaClient(DATALAKE_BUCKET)


@logger
def load_listing_info(exec_date):
    """
    returns a dataframe with
    'sk_house_listing',
    'publication_date'
    """
    logger.info(
        'm=load_listing_info'
        'exec_date={}, '
        'msg=downloading the listing data per day of publication '
        '(indicators of interest, etc)'.format(exec_date))
    path = os.path.join(
        SKYNET_QUERIES_DIR, 'listing_management/listing_information.sql')
    with open(path, 'r') as fd:
        query = fd.read()
    lid = athena.execute_query_and_wait_for_results(
        query, s3_bucket=SKYNET_BUCKET,
        bucket_folder_path=INPUT_PATH.format(exec_date))
    return lid


@logger
def load_historical_ioi(exec_date):
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
    logger.info(
        'm=load_historical_ioi'
        'exec_date={}, '
        'msg=downloading the listing data per day of publication '
        '(indicators of interest, etc)'.format(exec_date))
    path = os.path.join(
        SKYNET_QUERIES_DIR,
        'listing_management/indicators_of_interest_by_date.sql')
    with open(path, 'r') as fd:
        query = fd.read()
    hid = athena.execute_query_and_wait_for_results(
        query, s3_bucket=SKYNET_BUCKET,
        bucket_folder_path=INPUT_PATH.format(exec_date))
    return hid


def build_raw_data(**kwargs):
    logger.info('m=build_raw_data, kwargs={}'.format(kwargs))
    exec_date = (
        kwargs.get('execution_date') + timedelta(days=1)
    ).strftime('%Y-%m-%d')
    lid = load_listing_info(exec_date)
    hid = load_historical_ioi(exec_date)

    xcom.xcom_push(kwargs.get('ti'), key='lid', k_value=lid)
    xcom.xcom_push(kwargs.get('ti'), key='hid', k_value=hid)


def train_model(**kwargs):
    """gets the names of the datasets from the env variable
    and creates a sagemaker instance to 'train' the model (in our case,
    to make predictions)
    """
    logger.info('train_model, kwargs={}'.format(kwargs))

    lid = xcom.xcom_pull(kwargs.get('ti'), key='lid', dag_id=MAIN_DAG_NAME)
    hid = xcom.xcom_pull(kwargs.get('ti'), key='hid', dag_id=MAIN_DAG_NAME)

    exec_date = (
        kwargs.get('execution_date') + timedelta(days=1)
    ).strftime('%Y-%m-%d')

    params = kwargs.get('params')
    params.update(
        dict(
            raw_house_listing_file=lid + '.csv',
            raw_historical_data_file=hid + '.csv',
            date_begin=exec_date,
            date_end=exec_date
        )
    )

    job_name = 'skynet-listing-management-' + datetime.now().strftime(
        "%Y-%m-%d-%H-%M-%S")
    logger.info(
        'm=train_model, job_name={}, params={}'.format(job_name, params))

    model = sagemaker.estimator.Estimator(
        image_name=kwargs.get('image'),
        role=SAGEMAKER_ROLE,
        train_instance_count=1,
        train_instance_type='ml.m5.xlarge',
        output_path='s3://{}/{}'.format(SKYNET_BUCKET, TRAINING_PATH),
        hyperparameters=params)

    logger.info('m=train_model, starting training...')
    model.fit(
        's3://{}/{}'.format(
            SKYNET_BUCKET,
            INPUT_PATH.format(exec_date)),
        job_name=job_name,
        logs=False)

    xcom.xcom_push(kwargs.get('ti'), key='job_name', k_value=job_name)


def untar_output(**kwargs):
    """untars the output of the training (in our case, the predictions)
    """
    logger.info('untar_output, kwargs={}'.format(kwargs))

    bucket = boto3.resource('s3').Bucket(SKYNET_BUCKET)
    job_name = xcom.xcom_pull(
        kwargs.get('ti'), key='job_name', dag_id=MAIN_DAG_NAME)

    exec_date = (
        kwargs.get('execution_date') + timedelta(days=1)
    ).strftime('%Y-%m-%d')

    model_filename = os.path.join(
        TRAINING_PATH, job_name, 'output/model.tar.gz')
    model_obj = BytesIO(bucket.Object(model_filename).get()['Body'].read())

    logger.info('m=untar_output, msg=model loaded, decompressing output...')
    with tarfile.open(fileobj=model_obj) as tar:
        preds_json = tar.extractfile(
            'preds_{}.json'.format(exec_date)).read()

    logger.info(
        'm=untar_output, msg=saving predictions to {}.'.format(
            PREDICTIONS_PATH.format(exec_date)))
    preds_json_filename = os.path.join(
        PREDICTIONS_PATH.format(exec_date),
        'preds.json')
    bucket.Object(preds_json_filename).put(Body=preds_json)

    athena.upsert_single_partition(
        bucket_folder_path=os.path.join(
            SKYNET_BUCKET, 'listing-mgmt/data/predictions'),
        database='skynet',
        table='listing_management_predictions',
        partition_name='dt',
        partition_value=exec_date
    )


def restart_service(**kwargs):
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
    catchup=True
)

build_raw_data_op = BaseDAG.build_python_operator(
    dag=dag,
    task_id='build_raw_data',
    python_callable=build_raw_data,
    provide_context=True,
    op_kwargs=json.loads(SKYNET_LISTMGMT_KWARGS)
)

train_model_op = BaseDAG.build_python_operator(
    dag=dag,
    task_id='train_model',
    provide_context=True,
    python_callable=train_model,
    execution_timeout=timedelta(hours=8),
    op_kwargs=json.loads(SKYNET_LISTMGMT_KWARGS)
)

untar_output_op = BaseDAG.build_python_operator(
    dag=dag,
    task_id='untar_output',
    provide_context=True,
    python_callable=untar_output,
    op_kwargs=json.loads(SKYNET_LISTMGMT_KWARGS)
)

restart_service_op = BaseDAG.build_python_operator(
    dag=dag,
    task_id='restart_service',
    python_callable=restart_service,
    op_kwargs=json.loads(SKYNET_LISTMGMT_KWARGS)
)

build_raw_data_op >> train_model_op >> untar_output_op >> restart_service_op
