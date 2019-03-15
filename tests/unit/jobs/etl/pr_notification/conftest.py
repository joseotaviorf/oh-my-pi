import mock
import pytest

from bietlejuice.jobs.etl.pr_notification import SlackService, GithubService, SlackPullRequests, GithubPullRequests


@pytest.fixture(scope='session')
def slack_service():
    return SlackService(
        webhook_url=mock.ANY
    )


@pytest.fixture(scope='session')
def github_service():
    return GithubService(
        auth_token=mock.ANY
    )


@pytest.fixture(scope='session')
def slack_pull_requests():
    return SlackPullRequests(
        webhook_url=mock.ANY
    )


@pytest.fixture(scope='session')
def github_pull_requests():
    return GithubPullRequests(
        auth_token=mock.ANY,
        repo_name='repo_name'
    )
