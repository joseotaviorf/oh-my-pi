import requests
from qa_python_utils.default_logger import QuintoAndarLogger

logger = QuintoAndarLogger('SlackService')


class SlackService(object):
    SLACK_MESSAGE_TITLES = {
        'open': 'PRs still open for *review*! :face_with_monocle:\n\n',
        'approved': '\n\n\nPRs still open for *merge*! :approved:\n\n'
    }

    def __init__(self, webhook_url):
        self.webhook_url = webhook_url

    @staticmethod
    @logger(exclude='pull_requests')
    def build_slack_message(pull_requests, message_title):
        if pull_requests is None or len(pull_requests) == 0:
            logger.info('m=build_slack_message, msg=no pull requests to send')
            return

        message = message_title
        for pr_entry in pull_requests:
            if len(pr_entry['prs']) == 0:
                logger.info(
                    'm=build_slack_message, github_repo={}, msg=no pull requests in repository'.format(
                        pr_entry['repo']))
                return

            message += '\n*{}*\n'.format(pr_entry['repo'])
            for pr in pr_entry['prs']:
                message += '> {}'.format(pr)

        return message

    @logger
    def send_notifications_to_slack(self, message):
        requests.post(
            url=self.webhook_url,
            json={'text': message}
        )
