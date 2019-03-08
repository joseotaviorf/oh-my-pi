import requests

from conftest import mock


class TestSlackService(object):

    @mock.patch.object(requests, 'post')
    def test_send_notifications_to_slack(self, mock_requests_post, slack_service):
        # arrange
        json_field = 'text'
        message = mock.ANY
        mock_requests_post_call_args = {
            'url': mock.ANY,
            'json': {json_field: message}
        }

        # act
        slack_service.send_notifications_to_slack(message)

        # assert
        assert mock_requests_post.call_args[1] == mock_requests_post_call_args
