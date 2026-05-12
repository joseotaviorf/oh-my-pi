from os import path
from pkgutil import extend_path

__path__ = extend_path(__path__, __name__)

from bietlejuice.base.notification.gchat_webhooks_enum import GchatWebhooksEnum
from bietlejuice.base.notification.slack_webhooks_enum import SlackWebhooksEnum

SLACK_USER_GROUPS_MAPPING_PATH = (
    path.dirname(path.realpath(__file__)) + "/slack_user_groups_by_context.yml"
)

__all__ = [
    "GchatWebhooksEnum",
    "SlackWebhooksEnum",
    "SLACK_USER_GROUPS_MAPPING_PATH",
]
