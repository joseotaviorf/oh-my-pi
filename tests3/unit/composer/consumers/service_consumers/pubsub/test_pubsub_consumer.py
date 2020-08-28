import pytest
from bietlejuice.jobs.composer.consumers.service_consumers.pubsub.pubsub_sync_pull_consumer import (
    PubSubSubscriberSyncPullConsumer,
)


class TestPubsubConsumer:
    def test_constructor_fail_with_empty_parameters(self): 
        with pytest.raises(ValueError):
            assert PubSubSubscriberSyncPullConsumer("")

    def test_get_messages(self, pubsub_consumer):
        # arrange
        expected_ack_id = ['1', '2']
        expected_message = [[{'key': 'value_1'}], [{'key': 'value_2'}]]

        # act
        return_messages, return_ack_ids = pubsub_consumer.get_messages()

        # assert
        assert return_messages == expected_message
        assert return_ack_ids == expected_ack_id
