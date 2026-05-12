from unittest import mock

import pytest
import requests

from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message


class TestGChatService:
    @pytest.fixture(autouse=True)
    def requests_post(self):
        with mock.patch.object(requests, "post") as requests_post:
            yield requests_post

    def test_send_message_should_call_post_with_destination_and_formatted_payload(
        self, requests_post
    ):
        message = Message("test_content", "test_destination")
        GChatService.send_message(message)

        requests_post.assert_called_once_with(
            "test_destination", json={"text": "test_content"}
        )

    def test_send_message_should_return_false_when_response_raises(self, requests_post):
        requests_post.return_value.raise_for_status.side_effect = Exception(
            "test_exception"
        )
        message = Message("test_content", "test_destination")

        result = GChatService.send_message(message)

        assert result is False

    def test_send_message_should_return_true_when_response_does_not_raise(self):
        message = Message("test_content", "test_destination")

        result = GChatService.send_message(message)

        assert result is True

    def test_send_messages_should_call_post_for_each_message(self, requests_post):
        messages = [
            Message("test_content", "test_destination"),
            Message("test_content2", "test_destination2"),
        ]

        result = GChatService.send_messages(messages)

        assert requests_post.call_count == 2
        assert requests_post.call_args_list[0] == mock.call(
            "test_destination", json={"text": "test_content"}
        )
        assert requests_post.call_args_list[1] == mock.call(
            "test_destination2", json={"text": "test_content2"}
        )
        assert result is True

    def test_send_messages_should_return_false_when_any_message_fails(
        self, requests_post
    ):
        requests_post.return_value.raise_for_status.side_effect = Exception(
            "test_exception"
        )
        messages = [
            Message("test_content", "test_destination"),
            Message("test_content2", "test_destination2"),
        ]

        result = GChatService.send_messages(messages)

        assert requests_post.call_count == 2
        assert requests_post.call_args_list[0] == mock.call(
            "test_destination", json={"text": "test_content"}
        )
        assert requests_post.call_args_list[1] == mock.call(
            "test_destination2", json={"text": "test_content2"}
        )
        assert result is False
