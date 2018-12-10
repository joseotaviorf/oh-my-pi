from qa_python_utils.default_logger import QuintoAndarLogger
import requests

logger = QuintoAndarLogger('GithubPRNotification')


class GithubPRNotification(object):
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

    SLACK_MESSAGE_TITLES = {
        'open': 'PRs still open for *review*! :face_with_monocle:\n\n',
        'approved': 'PRs still open for *merge*! :approved:\n\n'
    }

    def __init__(self, github_auth_token, github_slack_webhook_url, github_repo_names):
        self.github_auth_token = github_auth_token
        self.github_slack_webhook_url = github_slack_webhook_url
        self.github_repo_names = github_repo_names

    @staticmethod
    @logger(exclude='json_response')
    def __get_pull_requests(json_response):
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
                    break

            if not is_pr_approved:
                open_prs.append(pr_append)

        return open_prs, approved_prs

    @logger
    def __get_json_response(self, repo_name):
        repo_json = {'query': GithubPRNotification.JSON_PAYLOAD['query'].replace('__REPO_NAME__', repo_name)}
        github = requests.post(
            url=GithubPRNotification.GITHUB_GRAPHQL_ENDPOINT,
            headers={'Authorization': 'bearer {}'.format(self.github_auth_token)},
            json=repo_json
        )
        _json_response = github.json()

        if _json_response['data']['repositoryOwner']['repository'] is None:
            raise Exception('m=__get_json_response, repository={}, msg=no data for repository'.format(repo_name))

        return _json_response

    @logger(exclude='pull_requests')
    def __build_slack_message(self, pull_requests, github_repo, slack_message_title):
        if len(pull_requests) == 0:
            logger.info(
                'm=__build_slack_message, github_repo={}, msg=no pull requests in repository'.format(github_repo))
            return

        slack_message_title += '\n*{}*\n'.format(github_repo)
        for pr in pull_requests:
            slack_message_title += '> {}'.format(pr)

        logger.info('m=__build_slack_message, github_repo={}, msg=sending notification to slack'.format(github_repo))
        requests.post(
            url=self.github_slack_webhook_url,
            json={'text': slack_message_title}
        )

    @logger
    def send_notifications_to_slack(self):
        for repo in self.github_repo_names:
            logger.info(
                'm=send_notifications_to_slack, repository={}, msg=getting pull requests from github repository'.format(
                    repo))

            json_response = self.__get_json_response(repo_name=repo)
            open_prs, approved_prs = GithubPRNotification.__get_pull_requests(json_response=json_response)

            self.__build_slack_message(
                pull_requests=open_prs,
                github_repo=repo,
                slack_message_title=GithubPRNotification.SLACK_MESSAGE_TITLES['open']
            )

            self.__build_slack_message(
                pull_requests=approved_prs,
                github_repo=repo,
                slack_message_title=GithubPRNotification.SLACK_MESSAGE_TITLES['approved']
            )
