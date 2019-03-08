import requests

from conftest import pytest, mock


class TestGithubService(object):

    @mock.patch.object(requests, 'post')
    def test_get_json_response(self, mock_requests_post, github_service):
        # arrange
        graphql_query = mock.ANY
        graphql_post = {
            'url': mock.ANY,
            'headers': {'Authorization': 'bearer {}'.format(mock.ANY)},
            'json': {'query': graphql_query}
        }
        mock_requests_post.return_value.status_code = 200

        # act
        github_service.get_json_response(graphql_query)

        # assert
        assert mock_requests_post.call_args[1] == graphql_post

    @mock.patch.object(requests, 'post')
    @pytest.mark.parametrize('status_code', [201, 500, 404, 400, 502, 503])
    def test_get_json_response_with_failed_status(self, mock_requests_post, github_service, status_code):
        # arrange
        graphql_query = mock.ANY
        mock_requests_post.return_value.status_code = status_code

        # act & assert
        with pytest.raises(RuntimeError):
            github_service.get_json_response(graphql_query)
