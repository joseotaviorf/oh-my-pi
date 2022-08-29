from os import path

from bietlejuice.base.notification.slack_webhooks_enum import SlackWebhooksEnum


SLACK_USER_GROUPS_MAPPING_PATH = (
    path.dirname(path.realpath(__file__)) + "/slack_user_groups_by_context.yml"
)
