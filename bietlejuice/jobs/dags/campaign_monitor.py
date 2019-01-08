import json
from datetime import datetime

from airflow.models import DAG

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.campaign_monitor.campaign import CampaignMonitorCampaignFactory

# env vars
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
cm_auth_dict = json.loads(env.get_airflow_env_var('campaign-monitor-authorization'))

MAIN_DAG_NAME = 'bi-campaign-monitor'
MAIN_START_DATE = datetime(2015, 8, 1)
MAIN_SCHEDULE_INTERVAL = '30 0 * * *'


# functions
def get_campaign_data(_class, **kwargs):
    campaign_obj = CampaignMonitorCampaignFactory.factory(
        _class=_class,
        s3_bucket=s3_bucket,
        cm_auth=cm_auth_dict,
        execution_date=kwargs['execution_date']
    )

    campaign_obj.request_campaign_data()


# dags
main_dag = DAG(
    dag_id=MAIN_DAG_NAME,
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    schedule_interval=env.convert_to_utc_schedule(MAIN_SCHEDULE_INTERVAL),
    max_active_runs=1
)

# operators
task_opens = BaseDAG.build_quintoandar_python_operator(
    task_id='opens',
    provide_context=True,
    python_callable=get_campaign_data,
    dag=main_dag,
    op_kwargs={'_class': 'opens'}
)

task_bounces = BaseDAG.build_quintoandar_python_operator(
    task_id='bounces',
    provide_context=True,
    python_callable=get_campaign_data,
    dag=main_dag,
    op_kwargs={'_class': 'bounces'}
)

task_clicks = BaseDAG.build_quintoandar_python_operator(
    task_id='clicks',
    provide_context=True,
    python_callable=get_campaign_data,
    dag=main_dag,
    op_kwargs={'_class': 'clicks'}
)

task_spams = BaseDAG.build_quintoandar_python_operator(
    task_id='spams',
    provide_context=True,
    python_callable=get_campaign_data,
    dag=main_dag,
    op_kwargs={'_class': 'spam'}
)

task_recipients = BaseDAG.build_quintoandar_python_operator(
    task_id='recipients',
    provide_context=True,
    python_callable=get_campaign_data,
    dag=main_dag,
    op_kwargs={'_class': 'recipients'}
)

task_unsubscribes = BaseDAG.build_quintoandar_python_operator(
    task_id='unsubscribes',
    provide_context=True,
    python_callable=get_campaign_data,
    dag=main_dag,
    op_kwargs={'_class': 'unsubscribes'}
)
