import json
import os
import sys
from datetime import datetime

import pandas as pd
from airflow.models import DAG
from qa_python_utils.default_logger import logger, _logger
from jobs.newetl.amplitude.amplitude_etl import AmplitudeETL
from airflow.operators import QuintoAndarPythonOperator

here = os.path.dirname(os.path.realpath(__file__))
sys.path.append(os.path.join(here, '../'))


@logger(exclude='kwargs')
def load_data(**kwargs):
    execution_date = kwargs['execution_date']
    amplitude_etl = AmplitudeETL(execution_date, )

    df_raw = amplitude_etl.get_all_columns()
    if df_raw.empty:
        _logger.warn('m=__main__, msg=empty dataframe')
    else:
        df_raw_json = pd.io.json.json_normalize(
            df_raw.event_data.apply(json.loads))
        df_raw_json['dt'] = df_raw['dt']

        df_properties = amplitude_etl.get_properties_as_df()
        df_raw_json = amplitude_etl.insert_new_columns(
            df=df_raw,
            df_props=df_properties,
            df_json=df_raw_json,
            properties='user_properties',
            prefix='u_')
        df_raw_json = amplitude_etl.insert_new_columns(
            df=df_raw,
            df_props=df_properties,
            df_json=df_raw_json,
            properties='event_properties',
            prefix='e_')

        amplitude_etl.create_parquets(df_raw_json)


@logger(exclude='kwargs')
def merge_users(**kwargs):
    execution_date = kwargs['execution_date']

    amplitude_etl = AmplitudeETL(execution_date)
    amplitude_etl.merge_user_ids()


dag = DAG(
    dag_id='bi-amplitude-etl',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2017, 11, 29, 0, 0),
    schedule_interval='0 4 * * *',
    max_active_runs=1)

load_events_data_to_clean_task = QuintoAndarPythonOperator(
    dag=dag,
    task_id='load_events_data_to_clean',
    provide_context=True,
    python_callable=load_data)

merge_users_task = QuintoAndarPythonOperator(
    dag=dag,
    task_id='merge_users',
    provide_context=True,
    python_callable=load_data)

load_events_data_to_clean_task.set_downstream(merge_users_task)
