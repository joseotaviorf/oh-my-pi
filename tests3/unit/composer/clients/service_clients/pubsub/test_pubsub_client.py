from unittest import mock
import pytest
from bietlejuice.jobs.composer.clients.service_clients.pubsub.pubsub_sync_pull_client import (
    PubSubSubscriberSyncPullClient,
)


class TestPubsubClient:
    @pytest.mark.parametrize(
        "project_id, subscription_id",
        [(1, 2), (None, "subscription_id"), ("project_id", None), (None, None)],
    )
    def test_constructor_fail_with_non_string_parameters(
        self, project_id, subscription_id
    ):
        with pytest.raises(TypeError):
            assert PubSubSubscriberSyncPullClient(project_id, subscription_id)

    @mock.patch.object(PubSubSubscriberSyncPullClient, "_client")
    def test__subscription_path(self, mocked_client, pubsub_client):
        # arrange
        subscription_path = "projects/project_id/subscriptions/subscription_id"
        mocked_client.subscription_path.return_value = subscription_path

        # act
        return_get_subscription_path = pubsub_client._subscription_path

        # assert
        assert return_get_subscription_path == subscription_path

    @pytest.mark.parametrize(
        "session_initial_value, expected_return",
        [(None, "client_1"), ("client_2", "client_2")],
    )
    @mock.patch("google.cloud.pubsub_v1.SubscriberClient")
    def test__client(
        self, mocked_client, pubsub_client, session_initial_value, expected_return
    ):
        # arrange
        mocked_client.return_value = "client_1"
        pubsub_client._session = session_initial_value

        # act
        return_client = pubsub_client._client

        # assert
        assert return_client == expected_return

    @mock.patch.object(PubSubSubscriberSyncPullClient, "_client")
    def test_request_messages(self, mocked_request_messages, pubsub_client):
        # arrange
        max_messages = 300
        mocked_request_messages.pull.return_value = "response"

        # act
        return_request_messages = pubsub_client.request_messages(max_messages)

        # assert
        assert return_request_messages == "response"

    def test_request_messages_fail_invalid_type(self, pubsub_client):
        with pytest.raises(TypeError):
            assert pubsub_client.request_messages("max_messages")

    @pytest.mark.parametrize("max_messages", [-1, 1003])
    def test_request_messages_fail_invalid_range(self, pubsub_client, max_messages):
        with pytest.raises(ValueError):
            assert pubsub_client.request_messages(max_messages)

    def test_acknowledge_messages_fail_invalid_type(self, pubsub_client):
        with pytest.raises(TypeError):
            assert pubsub_client.acknowledge_messages("ack_ids")

    def test_acknowledge_messages_fail_with_empty_list(self, pubsub_client):
        with pytest.raises(ValueError):
            assert pubsub_client.acknowledge_messages([])
