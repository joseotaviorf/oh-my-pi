import json
from datetime import datetime

from airflow.models import DAG

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.pr_notification import GithubService, SlackService

# env vars
GITHUB_REPOS = json.loads(env.get_airflow_env_var('github_repos'))
PR_NOTIFICATION_AUTH = json.loads(env.get_airflow_env_var('pr-notification-authorization'))

# global vars
MAIN_DAG_ID = 'bi-github-pr-notifications'
MAIN_START_DATE = datetime(2018, 1, 1)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 9-20/3 * * 1-5')


# functions
def send_notifications_to_slack():
    github_service = GithubService(
        auth_token=PR_NOTIFICATION_AUTH['github_auth']['token'],
        repo_names=GITHUB_REPOS['names']
    )
    slack_service = SlackService(webhook_url=PR_NOTIFICATION_AUTH['github_auth']['slack_webhook'])

    full_message = ''
    all_prs = {
        'open': [],
        'approved': []
    }
    for repo_name in github_service.repo_names:
        json_response = github_service.get_json_response(repo_name=repo_name)
        open_prs, approved_prs = GithubService.extract_pull_requests(json_response=json_response)

        if len(open_prs) > 0:
            all_prs['open'].append({
                'repo': repo_name,
                'prs': open_prs
            })

        if len(approved_prs) > 0:
            all_prs['approved'].append({
                'repo': repo_name,
                'prs': approved_prs
            })

    # build slack messages for opened and approved Github PRs
    full_message += SlackService.build_slack_message(
        pull_requests=all_prs['open'],
        message_title=SlackService.SLACK_MESSAGE_TITLES['open']
    )
    full_message += SlackService.build_slack_message(
        pull_requests=all_prs['approved'],
        message_title=SlackService.SLACK_MESSAGE_TITLES['approved'])

    # send only one message to Slack
    slack_service.send_notifications_to_slack(full_message)


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
github_pr_notification_task = BaseDAG.build_python_operator(
    task_id='send_notifications_to_slack',
    python_callable=send_notifications_to_slack,
    dag=main_dag
)
