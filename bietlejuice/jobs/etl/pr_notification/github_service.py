import requests
from qa_python_utils.default_logger import QuintoAndarLogger

logger = QuintoAndarLogger('GithubService')


class GithubService(object):
    JSON_PAYLOAD = {
        'query': """{
              repositoryOwner(login: "quintoandar") {
                repository(name: "__REPO_NAME__") {
                  name
                  pullRequests(last: 100, states: OPEN) {
                    edges {
                      node {
                        state
                        title
                        author {
                          login
                        }
                        url
                        reviews(last: 100) {
                          edges {
                            node {
                              state
                              author {
                                login
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }"""
    }

    GITHUB_GRAPHQL_ENDPOINT = 'https://api.github.com/graphql'

    def __init__(self, auth_token, repo_names):
        self.auth_token = auth_token
        self.repo_names = repo_names

    @logger
    def get_json_response(self, repo_name):
        repo_json = {'query': GithubService.JSON_PAYLOAD['query'].replace('__REPO_NAME__', repo_name)}
        github = requests.post(
            url=GithubService.GITHUB_GRAPHQL_ENDPOINT,
            headers={'Authorization': 'bearer {}'.format(self.auth_token)},
            json=repo_json
        )

        _json_response = github.json()
        if _json_response['data']['repositoryOwner']['repository'] is None:
            raise Exception('m=get_json_response, repository={}, msg=no data for repository'.format(repo_name))

        return _json_response

    @staticmethod
    @logger(exclude='json_response')
    def extract_pull_requests(json_response):
        open_prs = []
        approved_prs = []
        repo = json_response['data']['repositoryOwner']['repository']
        for prs in repo['pullRequests']['edges']:
            _title = prs['node']['title']
            _author = prs['node']['author']['login']
            _url = prs['node']['url']

            pr_append = '*<{}|{}>* ({})\n'.format(_url, _title, _author)

            if len(prs['node']['reviews']['edges']) <= 0:
                open_prs.append(pr_append)
                continue

            is_pr_approved = False
            for rev in prs['node']['reviews']['edges']:
                if rev['node']['state'] == 'APPROVED':
                    approved_prs.append(pr_append)
                    is_pr_approved = True
                    continue

                if rev['node']['state'] == 'CHANGES_REQUESTED':
                    approved_prs.append(pr_append)
                    is_pr_approved = False
                    break

            if not is_pr_approved:
                open_prs.append(pr_append)

        return open_prs, approved_prs
