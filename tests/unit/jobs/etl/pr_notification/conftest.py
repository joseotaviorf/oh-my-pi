import mock
import pytest

from bietlejuice.jobs.etl.pr_notification import SlackService, GithubService


@pytest.fixture(scope='session')
def slack_service():
    return SlackService(
        webhook_url=mock.ANY
    )


@pytest.fixture(scope='session')
def github_service():
    return GithubService(
        auth_token=mock.ANY,
        repo_names=mock.ANY
    )
