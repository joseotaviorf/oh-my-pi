import logging
from typing import List

import requests

from bietlejuice.services.messaging_services.message import Message


class GChatService:
    _THREAD_REPLY_OPTION = "REPLY_MESSAGE_FALLBACK_TO_NEW_THREAD"

    @staticmethod
    def send_message(message: Message) -> bool:
        """
        Sends a message to a GChat webhook. Returns True if the message was sent
        successfully, False otherwise.

        When ``message.thread_key`` is set, posts into (or starts) a Google Chat thread
        via ``messageReplyOption=REPLY_MESSAGE_FALLBACK_TO_NEW_THREAD``.
        """

        payload: dict = {"text": message.content}
        destination = message.destination
        if message.thread_key:
            separator = "&" if "?" in destination else "?"
            destination = (
                f"{destination}{separator}messageReplyOption="
                f"{GChatService._THREAD_REPLY_OPTION}"
            )
            payload["thread"] = {"threadKey": message.thread_key}
        response = requests.post(destination, json=payload)
        try:
            response.raise_for_status()
        except Exception as e:
            logging.warning(
                f"m=send_message, msg=Gchat message was not sent, check"
                f" the webhook url: {message.destination}, payload:{payload},"
                f" error: {e}"
            )
            return False
        return True

    @staticmethod
    def send_messages(messages: List[Message]) -> bool:
        """
        Sends a list of messages to a GChat webhook. Returns True if all messages
        were sent successfully, False otherwise.
        """

        all_success = all([GChatService.send_message(message) for message in messages])
        return all_success
