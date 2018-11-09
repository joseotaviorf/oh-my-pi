import json
from datetime import datetime

from airflow.models import DAG

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.github_pr_notification import GithubPRNotification

# env vars
GITHUB_REPOS = json.loads(env.get_airflow_env_var('github_repos'))
GITHUB_AUTH = json.loads(env.get_airflow_env_var('github_authorization'))

# global vars
MAIN_DAG_ID = 'bi-github-pr-notifications'
MAIN_START_DATE = datetime(2018, 1, 1)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 9-20 * * 1-5')


# functions
def send_notifications_to_slack():
    github_pr_notification = GithubPRNotification(
        github_auth_token=GITHUB_AUTH['token'],
        github_slack_webhook_url=GITHUB_AUTH['slack_webhook'],
        github_repo_names=GITHUB_REPOS['names']
    )

    github_pr_notification.send_notifications_to_slack()


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
github_pr_notification_task = BaseDAG.build_quintoandar_python_operator(
    task_id='send_notifications_to_slack',
    python_callable=send_notifications_to_slack,
    dag=main_dag
)
