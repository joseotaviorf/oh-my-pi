import mock
import pytest
import requests


class TestSlackService(object):

    def test_build_slack_message(self, slack_service):
        # arrange
        message_title = 'message_title'
        pull_requests = [{'repo': 'repo', 'prs': ['first_pr', 'second_pr']}]

        # act
        result = slack_service.build_slack_message(
            pull_requests=pull_requests,
            message_title=message_title
        )

        # assert
        assert result == '{}\n*{}*\n> {}> {}'.format(message_title,
                                                     pull_requests[0]['repo'],
                                                     pull_requests[0]['prs'][0],
                                                     pull_requests[0]['prs'][1])

    @pytest.mark.parametrize('pull_requests', [None, []])
    def test_build_slack_message_with_no_pull_requests(self, slack_service, pull_requests):
        # arrange
        message_title = mock.ANY

        # act
        result = slack_service.build_slack_message(
            pull_requests=pull_requests,
            message_title=message_title
        )

        # assert
        assert result is None

    def test_build_slack_message_with_no_pr_entries(self, slack_service):
        # arrange
        message_title = mock.ANY
        pull_requests = [{'repo': mock.ANY, 'prs': []}]

        # act
        result = slack_service.build_slack_message(
            pull_requests=pull_requests,
            message_title=message_title
        )

        # assert
        assert result is None

    @mock.patch.object(requests, 'post')
    def test_send_notifications_to_slack(self, mock_requests_post, slack_service):
        # arrange
        json_field = 'text'
        message = mock.ANY
        post_url = mock.ANY

        # act
        slack_service.send_notifications_to_slack(message)

        # assert
        assert mock_requests_post.call_args[1] == {
            'url': post_url,
            'json': {json_field: message}
        }
