from bietlejuice.jobs.etl.pr_notification.github_service import GithubService
from qa_python_utils.default_logger import QuintoAndarLogger

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
        self.graphql_query = GithubPullRequests.PULL_REQUESTS_QUERY['query'].replace('__REPO_NAME__', repo_name)

    @logger
    def extract_pull_requests(self):
        no_reviewed_prs = []
        reviewed_prs = []
        approved_prs = []

        json_response = self.get_json_response(self.graphql_query)
        repo = json_response['data']['repositoryOwner']['repository']
        if repo is None:
            api_msg_error = 'No error message was received from API'
            if 'errors' in json_response:
                api_msg_error = ', '.join([error['message'] for error in json_response['errors']])
            raise RuntimeError(
                'm=extract_pull_requests, repository={}, msg={}'.format(self.repo_name, api_msg_error))

        for prs in repo['pullRequests']['edges']:
            _title = prs['node']['title'].encode('ascii', 'ignore').decode('ascii')  # removing non-ascii chars
            _author = prs['node']['author']['login']
            _url = prs['node']['url']

            pr_append = '*<{}|{}>* ({})\n'.format(_url, _title, _author)

            # No one reviewed
            if not prs['node']['reviews']['edges']:
                no_reviewed_prs.append(pr_append)
            else:
                is_approved = False
                is_reviewed = False
                for rev in prs['node']['reviews']['edges']:
                    if rev['node']['state'] == 'APPROVED':
                        # If approved, nothing else matters
                        approved_prs.append(pr_append)
                        is_approved = True
                        break

                    if rev['node']['state'] in ('CHANGES_REQUESTED', 'COMMENTED'):
                        is_reviewed = True

                # If reviewed only consider if not approved, otherwise it will be duplicated
                if is_reviewed and not is_approved:
                    reviewed_prs.append(pr_append)

        # sort
        no_reviewed_prs.sort()
        reviewed_prs.sort()
        approved_prs.sort()

        return no_reviewed_prs, reviewed_prs, approved_prs
