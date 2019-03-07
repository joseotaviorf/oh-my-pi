import requests
from qa_python_utils.default_logger import QuintoAndarLogger

logger = QuintoAndarLogger('GithubService')


class GithubService(object):
    GITHUB_GRAPHQL_ENDPOINT = 'https://api.github.com/graphql'

    def __init__(self, auth_token):
        self.auth_token = auth_token

    def _get_json_response(self, graphql_query):
        github_response = requests.post(
            url=GithubService.GITHUB_GRAPHQL_ENDPOINT,
            headers={'Authorization': 'bearer {}'.format(self.auth_token)},
            json={'query': graphql_query}
        )

        if github_response.status_code != 200:
            raise RuntimeError(
                'm=_get_json_response, status_code={}, '.format(github_response.status_code, github_response.json()))

        return github_response.json()
