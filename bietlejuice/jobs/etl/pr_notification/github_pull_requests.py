from qa_python_utils.default_logger import QuintoAndarLogger

from bietlejuice.jobs.etl.pr_notification.github_service import GithubService

logger = QuintoAndarLogger('GithubPullRequests')


class GithubPullRequests(GithubService):
    PULL_REQUESTS_QUERY = {
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

    def __init__(self, auth_token, repo_name):
        super(GithubPullRequests, self).__init__(auth_token)
        self.repo_name = repo_name
        self.graphql_query = {
            'query': GithubPullRequests.PULL_REQUESTS_QUERY['query'].replace('__REPO_NAME__', repo_name)
        }

    @logger
    def extract_pull_requests(self):
        open_prs = []
        approved_prs = []

        json_response = self.get_json_response(self.graphql_query)
        repo = json_response['data']['repositoryOwner']['repository']
        if repo is None:
            raise RuntimeError(
                'm=extract_pull_requests, repository={}, msg=no data for repository'.format(self.repo_name))

        for prs in repo['pullRequests']['edges']:
            _title = prs['node']['title']
            _author = prs['node']['author']['login']
            _url = prs['node']['url']

            pr_append = '*<{}|{}>* ({})\n'.format(_url, _title, _author)

            if not prs['node']['reviews']['edges']:
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
