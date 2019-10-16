from qa_python_utils.default_logger import QuintoAndarLogger

from bietlejuice.jobs.etl.pr_notification.slack_service import SlackService

logger = QuintoAndarLogger('SlackPullRequests')


class SlackPullRequests(SlackService):
    SLACK_MESSAGE_TITLES = {
        'no_reviewed_prs': 'PRs still open for *review*! :face_with_monocle:\n\n',
        'reviewed_prs': '\n\n\nPRs *reviewed* but require action! :construction:\n\n',
        'approved': '\n\n\nPRs ready to *merge*! :approved:\n\n'
    }

    def __init__(self, webhook_url):
        super(SlackPullRequests, self).__init__(webhook_url)

    @staticmethod
    @logger(exclude='pull_requests')
    def build_slack_message(pull_requests, message_title):
        if pull_requests is None or not pull_requests:
            logger.info('m=build_slack_message, msg=no pull requests to send')
            return
        message = message_title
        for pr_entry in pull_requests:
            if not pr_entry['prs']:
                logger.info(
                    'm=build_slack_message, github_repo={}, msg=no pull requests in repository'.format(
                        pr_entry['repo']))
                return

            message += '\n*{}*\n'.format(pr_entry['repo'])
            for pr in pr_entry['prs']:
                message += '> {}'.format(pr)

        return message
