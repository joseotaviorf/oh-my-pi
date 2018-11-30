import json
import os
import tarfile
from datetime import datetime, timedelta
from io import BytesIO

import boto3
import kubernetes.client as kube
import sagemaker
from airflow.models import DAG
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.kafka.dispatcher import KafkaDispatcher

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags import SKYNET_QUERIES_DIR
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.dags.util import xcom

MAIN_DAG_NAME = 'skynet-recommender'
MAIN_START_DATE = datetime(2018, 9, 30)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 0 * * 1')

DATALAKE_BUCKET = env.get_airflow_env_var('bi-datalake-s3-bucket')
SKYNET_BUCKET = env.get_airflow_env_var('SKYNET_BUCKET')
SAGEMAKER_ROLE = env.get_airflow_env_var('SAGEMAKER_ROLE')
SKYNET_RECOMMENDER_KWARGS = env.get_airflow_env_var('SKYNET_RECOMMENDER_KWARGS')
SKYNET_KUBERNETES_TOKEN = env.get_airflow_env_var('SKYNET_KUBERNETES_TOKEN')
KUBERNETES_API_ENDPOINT = env.get_airflow_env_var('KUBERNETES_API_ENDPOINT')

TRAINING_PATH = 'listing2vec/training'
INPUT_PATH = 'listing2vec/data/raw/dt={}'
RESULT_PATH = 'listing2vec/data/result/dt={}'
EMBEDDINGS_PATH = 'listing2vec/embeddings/dt={}'
COLD_PATH = 'listing2vec/cold/dt={}'

logger = QuintoAndarLogger(MAIN_DAG_NAME)
athena = AthenaClient(DATALAKE_BUCKET)

env.set_airflow_var_to_local_env(
    'AWS_SECRET_ACCESS_KEY',
    'AWS_ACCESS_KEY_ID',
    'AWS_DEFAULT_REGION',
    'KAFKA_BOOTSTRAP_SERVERS',
)


def build_raw_data(**kwargs):
    week_span = kwargs.get('week_span', 12)

    end_date = kwargs.get('execution_date') + timedelta(days=7)
    start_date = end_date - timedelta(weeks=week_span)

    with open(os.path.join(
            SKYNET_QUERIES_DIR, 'recommender/raw_data.sql'), 'r') as f:
        q = f.read()
        q = (q.replace('__START_YM__', start_date.strftime('%Y-%m'))
             .replace('__END_YM__', end_date.strftime('%Y-%m'))
             .replace('__START_DATE__', start_date.strftime('%Y-%m-%d'))
             .replace('__END_DATE__', end_date.strftime('%Y-%m-%d')))

        logger.info(
            'm=build_raw_data, start_date={}, end_date={}, '
            'msg=querying raw_data'.format(start_date, end_date))
        rid = athena.execute_query_and_wait_for_results(
            q, s3_bucket=SKYNET_BUCKET,
            bucket_folder_path=INPUT_PATH.format(end_date.strftime('%Y-%m-%d')))

    with open(os.path.join(
            SKYNET_QUERIES_DIR, 'recommender/house_info.sql'), 'r') as f:
        q = f.read()

        logger.info('m=build_raw_data, msg=querying house_info')
        hid = athena.execute_query_and_wait_for_results(
            q, s3_bucket=SKYNET_BUCKET,
            bucket_folder_path=INPUT_PATH.format(end_date.strftime('%Y-%m-%d')))

    xcom.xcom_push(kwargs.get('ti'), key='rid', k_value=rid)
    xcom.xcom_push(kwargs.get('ti'), key='hid', k_value=hid)


def train_model(**kwargs):
    rid = xcom.xcom_pull(kwargs.get('ti'), key='rid', dag_id=MAIN_DAG_NAME)
    hid = xcom.xcom_pull(kwargs.get('ti'), key='hid', dag_id=MAIN_DAG_NAME)
    exec_date = kwargs.get('execution_date') + timedelta(days=7)

    params = kwargs.get('params')
    params.update(
        dict(raw_filename=rid + '.csv', house_info_filename=hid + '.csv'))

    job_name = 'skynet-recommender-' + datetime.now().strftime(
        "%Y-%m-%d-%H-%M-%S")
    logger.info(
        'm=train_model, job_name={}, params={}'.format(job_name, params))

    model = sagemaker.estimator.Estimator(
        image_name=kwargs.get('image'),
        role=SAGEMAKER_ROLE,
        train_instance_count=1,
        train_instance_type='ml.m5.2xlarge',  # $0.538 per training hour
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
    bucket = boto3.resource('s3').Bucket(SKYNET_BUCKET)
    job_name = xcom.xcom_pull(
        kwargs.get('ti'), key='job_name', dag_id=MAIN_DAG_NAME)
    exec_date = kwargs.get('execution_date') + timedelta(days=7)

    model_filename = os.path.join(
        TRAINING_PATH, job_name, 'output/model.tar.gz')
    model_obj = BytesIO(bucket.Object(model_filename).get()['Body'].read())

    logger.info('m=untar_output, msg=model loaded, decompressing output...')
    with tarfile.open(fileobj=model_obj) as tar:
        emb = tar.extractfile('embeddings.json').read()
        results = tar.extractfile('results.pkl').read()
        cold = tar.extractfile('cold.gz').read()

    logger.info(
        'm=untar_output, msg=saving embeddings to {}.'.format(
            EMBEDDINGS_PATH.format(exec_date.strftime('%Y-%m-%d'))))
    emb_filename = os.path.join(
        EMBEDDINGS_PATH.format(exec_date.strftime('%Y-%m-%d')),
        'embeddings.json')
    bucket.Object(emb_filename).put(Body=emb)

    logger.info(
        'm=untar_output, msg=saving training result to {}.'.format(
            RESULT_PATH.format(exec_date.strftime('%Y-%m-%d'))))
    results_filename = os.path.join(
        RESULT_PATH.format(exec_date.strftime('%Y-%m-%d')), 'results.pkl')
    bucket.Object(results_filename).put(Body=results)

    logger.info(
        'm=untar_output, msg=saving cold embeddings model to {}.'.format(
            COLD_PATH.format(exec_date.strftime('%Y-%m-%d'))))
    cold_filename = os.path.join(
        COLD_PATH.format(exec_date.strftime('%Y-%m-%d')), 'cold.gz')
    bucket.Object(cold_filename).put(Body=cold)

    athena.upsert_single_partition(
        bucket_folder_path=os.path.join(
            SKYNET_BUCKET, 'listing2vec/embeddings'),
        database='skynet',
        table='listing2vec_embeddings',
        partition_name='dt',
        partition_value=exec_date.strftime('%Y-%m-%d')
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


def notify_sucess(**kwargs):
    dispatcher = KafkaDispatcher()
    dispatcher.dispatch_message(
        topic='SkynetRecommender',
        event_name='EmbeddingsProcessingFinished',
        payload={},
        source='airflow')


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
    provide_context=True,
    python_callable=build_raw_data,
    op_kwargs=json.loads(SKYNET_RECOMMENDER_KWARGS)
)

train_model_op = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='train_model',
    provide_context=True,
    python_callable=train_model,
    execution_timeout=timedelta(hours=8),
    op_kwargs=json.loads(SKYNET_RECOMMENDER_KWARGS)
)

untar_output_op = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='untar_output',
    provide_context=True,
    python_callable=untar_output,
    op_kwargs=json.loads(SKYNET_RECOMMENDER_KWARGS)
)

restart_service_op = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='restart_service',
    python_callable=restart_service,
    op_kwargs=json.loads(SKYNET_RECOMMENDER_KWARGS)
)

notify_success_op = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='notify success',
    python_callable=notify_sucess,
    op_kwargs=json.loads(SKYNET_RECOMMENDER_KWARGS)
)

build_raw_data_op >> train_model_op >> untar_output_op >> restart_service_op >> notify_success_op
