from airflow.models import DAG
from datetime import datetime

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.leads import LeadsReprocessor

env.set_airflow_var_to_local_env('EBDB')
bucket_datalake = env.get_airflow_env_var('bi-datalake-s3-bucket')
config_json = env.get_airflow_env_var('REPROCESS_LEADS_CONFIG')


def reprocess_leads(config_json):
    lr = LeadsReprocessor(config_json=config_json)
    json_leads = lr.get_leads()
    lr.send_leads(json_list=json_leads)


dag = DAG(
    dag_id='bi-reprocess-leads',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2019, 1, 1, 0, 0, 0),
    schedule_interval=None,
    max_active_runs=1
)

# Get and treat leads to be reprocessed
reprocess_leads_task = BaseDAG.build_python_operator(
    dag=dag,
    task_id='reprocess_leads',
    python_callable=reprocess_leads,
    op_kwargs={'config_json': config_json}
)
