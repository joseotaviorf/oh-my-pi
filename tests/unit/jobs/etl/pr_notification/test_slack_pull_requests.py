from conftest import pytest, mock, SlackPullRequests


class TestSlackService(object):

    def test_build_slack_message(self):
        # arrange
        message_title = 'message_title'
        pull_requests = [{'repo': 'repo', 'prs': ['first_pr', 'second_pr']}]
        formatted_message = '{}\n*{}*\n> {}> {}'.format(message_title,
                                                        pull_requests[0]['repo'],
                                                        pull_requests[0]['prs'][0],
                                                        pull_requests[0]['prs'][1])

        # act
        result = SlackPullRequests.build_slack_message(
            pull_requests=pull_requests,
            message_title=message_title
        )

        # assert
        assert result == formatted_message

    @pytest.mark.parametrize('pull_requests', [None, []])
    def test_build_slack_message_with_no_pull_requests(self, pull_requests):
        # arrange
        message_title = mock.ANY

        # act
        result = SlackPullRequests.build_slack_message(
            pull_requests=pull_requests,
            message_title=message_title
        )

        # assert
        assert result is None

    def test_build_slack_message_with_no_pr_entries(self):
        # arrange
        message_title = mock.ANY
        pull_requests = [{'repo': mock.ANY, 'prs': []}]

        # act
        result = SlackPullRequests.build_slack_message(
            pull_requests=pull_requests,
            message_title=message_title
        )

        # assert
        assert result is None
