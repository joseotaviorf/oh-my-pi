import json
import os
from datetime import datetime
from os import listdir
from os.path import isfile, join

from airflow.contrib.hooks.ssh_hook import SSHHook
from airflow.contrib.operators.sftp_operator import SFTPOperator, SFTPOperation
from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.kenshoo import Kenshoo
from qa_python_utils.aws.athena import AthenaClient

# env vars
SFTP_AUTH = json.loads(env.get_airflow_env_var('kenshoo-sftp-authorization'))
S3_BUCKET = env.get_airflow_env_var('bi-datalake-s3-bucket')
env.set_airflow_var_to_local_env('BI_DW', 'DATA_ACC_AWS_ACCESS_KEY_ID', 'DATA_ACC_AWS_SECRET_ACCESS_KEY')

# global vars
MAIN_DAG_ID = 'bi-kenshoo'
MAIN_START_DATE = datetime(2019, 1, 1)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 8 * * *')

# dag
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


# functions
def execute_athena_query(query_filename, ds, file_name, use_query_params, **kwargs):
    kenshoo = Kenshoo(
        execution_date=ds
    )
    data_acc_aws_access_key_id = os.environ.get('DATA_ACC_AWS_ACCESS_KEY_ID')
    data_acc_aws_secret_access_key = os.environ.get('DATA_ACC_AWS_SECRET_ACCESS_KEY')
    # using dependency injection instead of coupling classes
    athena_client = AthenaClient(S3_BUCKET, data_acc_aws_access_key_id, data_acc_aws_secret_access_key)
    kenshoo.save_file_from_athena_query_execution(query_filename=query_filename, athena_client=athena_client,
                                                  file_name=file_name,
                                                  query_params=dict(
                                                      {'dt': datetime.date(
                                                          kwargs['execution_date'])}) if use_query_params else None)


def execute_redshift_query(query_filename, ds, split_by_column=None, extra_params=None,
                           file_name=None, **kwargs):
    # Setting params
    query_params = {}
    if ds:
        query_params.update({'dt': str(ds)})
    if extra_params:
        query_params.update(**extra_params)

    kenshoo = Kenshoo(
        execution_date=ds
    )
    kenshoo.save_file_from_redshift_query_execution(query_filename=query_filename,
                                                    query_params=query_params,
                                                    split_by_column=split_by_column,
                                                    file_name=file_name)


def create_tasks_in_subdag(sub_dag_name):
    local_path = '/tmp'
    validation_prefix_list = ['kenshoo-visits_accomplished']

    local_dag = BaseSubDag(
        bucket=S3_BUCKET,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    list_files = [f for f in listdir(local_path) if isfile(join(local_path, f))]
    for item in list_files:
        for validation_item in validation_prefix_list:
            if validation_item in item:
                dag_prefix = validation_item.split('-')[-1]
                dag_suffix = (item.replace('.csv', '').replace(' ', '')),
                dag_suffix = dag_suffix[0]
                file_name = item

                SFTPOperator(
                    task_id='{}_{}'.format(dag_prefix, dag_suffix),
                    ssh_hook=ssh_hook,
                    local_filepath='{}/{}'.format(local_path, file_name),
                    remote_filepath='{}/{}.csv'.format(dag_prefix, file_name),
                    operation=SFTPOperation.PUT,
                    dag=local_dag,
                    retries=3
                )

    return local_dag


# hooks
ssh_hook = SSHHook(
    remote_host=SFTP_AUTH['host'],
    username=SFTP_AUTH['username'],
    password=SFTP_AUTH['password']
)

# operators
execute_adjust_search_offline_conversions_query_task = BaseDAG.build_python_operator(
    task_id='execute_adjust_search_offline_conversions_query',
    python_callable=execute_athena_query,
    provide_context=True,
    op_kwargs={'query_filename': 'adjust_search_offline_conversions.sql',
               'file_name': 'adjust_search_offline_conversions',
               'use_query_params': True},
    dag=main_dag
)

send_adjust_search_offline_conversions_data_task = SFTPOperator(
    task_id='send_adjust_search_offline_conversions_data',
    ssh_hook=ssh_hook,
    local_filepath='{}-{}{}.csv'.format(Kenshoo.CSV_PATH_PREFIX, 'adjust_search_offline_conversions', '{{ ds }}'),
    remote_filepath='query_result_{{ ds }}.csv',
    operation=SFTPOperation.PUT,
    dag=main_dag,
    retries=3
)

execute_visit_accomplished_query_task = BaseDAG.build_python_operator(
    task_id='execute_visit_accomplished_query',
    python_callable=execute_redshift_query,
    provide_context=True,
    op_kwargs={'query_filename': 'visits_accomplished.sql',
               'split_by_column': 'city_group'
               },
    dag=main_dag
)

send_visits_accomplished_query_task = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='send_visits_accomplished_query',
    sub_dag_func=create_tasks_in_subdag
)

execute_visit_schedule_confirmed_with_gclid_query_task = BaseDAG.build_python_operator(
    task_id='execute_visit_schedule_confirmed_with_gclid_query',
    python_callable=execute_athena_query,
    provide_context=True,
    op_kwargs={'query_filename': 'visit_schedule_confirmed_with_gclid.sql',
               'file_name': 'visit_schedule_confirmed_with_gclid',
               'use_query_params': True},
    dag=main_dag
)

send_visit_schedule_confirmed_with_gclid_query_task = SFTPOperator(
    task_id='send_visit_schedule_confirmed_with_gclid_query',
    ssh_hook=ssh_hook,
    local_filepath='{}-{}{}.csv'.format(Kenshoo.CSV_PATH_PREFIX, 'visit_schedule_confirmed_with_gclid', '{{ ds }}'),
    remote_filepath='visit_schedule_confirmed_with_gclid/visit_schedule_confirmed_{{ ds }}.csv',
    operation=SFTPOperation.PUT,
    dag=main_dag,
    retries=3
)

execute_users_with_active_contract_month_query_task = BaseDAG.build_python_operator(
    task_id='execute_users_with_active_contract_month_query',
    python_callable=execute_redshift_query,
    provide_context=True,
    op_kwargs={'query_filename': 'users_with_active_contract.sql',
               'extra_params': {'days': -30},
               'file_name': 'users_with_active_contract_month'
               },
    dag=main_dag
)

send_users_with_active_contract_month_task = SFTPOperator(
    task_id='send_users_with_active_contract_month',
    ssh_hook=ssh_hook,
    local_filepath='{}-{}{}.csv'.format(Kenshoo.CSV_PATH_PREFIX, 'users_with_active_contract_month', '{{ ds }}'),
    remote_filepath='users_with_active_contract/monthly/monthly_users_with_active_contract.csv',
    operation=SFTPOperation.PUT,
    dag=main_dag,
    retries=3
)


execute_users_with_active_contract_year_query_task = BaseDAG.build_python_operator(
    task_id='execute_users_with_active_contract_year_query',
    python_callable=execute_redshift_query,
    provide_context=True,
    op_kwargs={'query_filename': 'users_with_active_contract.sql',
               'extra_params': {'days': -365},
               'file_name': 'users_with_active_contract_year'
               },
    dag=main_dag
)

send_users_with_active_contract_year_task = SFTPOperator(
    task_id='send_users_with_active_contract_year',
    ssh_hook=ssh_hook,
    local_filepath='{}-{}{}.csv'.format(Kenshoo.CSV_PATH_PREFIX, 'users_with_active_contract_year', '{{ ds }}'),
    remote_filepath='users_with_active_contract/yearly/yearly_users_with_active_contract.csv',
    operation=SFTPOperation.PUT,
    dag=main_dag,
    retries=3
)

# flow
execute_adjust_search_offline_conversions_query_task >> send_adjust_search_offline_conversions_data_task
send_visits_accomplished_query_task.set_upstream(execute_visit_accomplished_query_task)
execute_visit_schedule_confirmed_with_gclid_query_task >> send_visit_schedule_confirmed_with_gclid_query_task
execute_users_with_active_contract_month_query_task >> send_users_with_active_contract_month_task
execute_users_with_active_contract_year_query_task >> send_users_with_active_contract_year_task
