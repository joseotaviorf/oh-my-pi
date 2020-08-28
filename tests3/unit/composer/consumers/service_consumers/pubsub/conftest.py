import pytest
from unittest.mock import Mock

from bietlejuice.jobs.composer.consumers.service_consumers.pubsub.pubsub_sync_pull_consumer import (
    PubSubSubscriberSyncPullConsumer,
)


class MockedMessageData:
    def __init__(self, message_value):
        self.data = f'[{{"key": "{message_value}"}}]'


class MockedReceivedMessage:
    def __init__(self, ack_id, message_value):
        self.ack_id = ack_id
        self.message = MockedMessageData(message_value)


class MockedPullResponse:
    def __init__(self):
        mocked_received_message_1 = MockedReceivedMessage('1', 'value_1')
        mocked_received_message_2 = MockedReceivedMessage('2', 'value_2')
        self.received_messages = [mocked_received_message_1, mocked_received_message_2]


@pytest.fixture
def pubsub_consumer():
    client = Mock()
    client.request_messages.return_value = MockedPullResponse()
    return PubSubSubscriberSyncPullConsumer(client)
