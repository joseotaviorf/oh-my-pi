import json
from datetime import datetime

from airflow.models import DAG
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.pr_notification import GithubPullRequests, SlackPullRequests

# env vars
GITHUB_REPOS = json.loads(env.get_airflow_env_var('github_repos'))
PR_NOTIFICATION_AUTH = json.loads(env.get_airflow_env_var('pr-notification-authorization'))

# global vars
MAIN_DAG_ID = 'bi-github-pr-notifications'
MAIN_START_DATE = datetime(2018, 1, 1)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule('0 9-20/3 * * 1-5')


# functions
def send_notifications_to_slack():
    full_message = ''
    all_prs = {
        'no_reviewed_prs': [],
        'reviewed_prs': [],
        'approved': []
    }
    for repo_name in GITHUB_REPOS['names']:
        github_pull_requests = GithubPullRequests(
            auth_token=PR_NOTIFICATION_AUTH['github_auth']['token'],
            repo_name=repo_name
        )

        no_reviewed_prs, reviewed_prs, approved_prs = github_pull_requests.extract_pull_requests()
        if no_reviewed_prs:
            all_prs['no_reviewed_prs'].append({
                'repo': repo_name,
                'prs': no_reviewed_prs
            })

        if reviewed_prs:
            all_prs['reviewed_prs'].append({
                'repo': repo_name,
                'prs': reviewed_prs
            })

        if approved_prs:
            all_prs['approved'].append({
                'repo': repo_name,
                'prs': approved_prs
            })

    # build slack messages for Github PRs
    full_message += SlackPullRequests.build_slack_message(
        pull_requests=all_prs['no_reviewed_prs'],
        message_title=SlackPullRequests.SLACK_MESSAGE_TITLES['no_reviewed_prs']
    )
    full_message += SlackPullRequests.build_slack_message(
        pull_requests=all_prs['reviewed_prs'],
        message_title=SlackPullRequests.SLACK_MESSAGE_TITLES['reviewed_prs']
    )
    full_message += SlackPullRequests.build_slack_message(
        pull_requests=all_prs['approved'],
        message_title=SlackPullRequests.SLACK_MESSAGE_TITLES['approved'])

    # send only one message to Slack
    slack_service = SlackPullRequests(webhook_url=PR_NOTIFICATION_AUTH['github_auth']['slack_webhook'])
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
