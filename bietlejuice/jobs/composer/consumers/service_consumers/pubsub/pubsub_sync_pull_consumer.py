import json

from quintoandar_logger import QuintoAndarLogger
from time import time

logger = QuintoAndarLogger("PubSubSubscriberSyncPullConsumer")


class PubSubSubscriberSyncPullConsumer:

    DEFAULT_MAX_MESSAGES_PER_REQUEST = 300

    @logger
    def __init__(self, pubsub_client):
        if not pubsub_client:
            raise ValueError("m=__init__, msg=pubsub_client cannot be empty")

        self._pubsub_client = pubsub_client

    @logger(exclude_return=True)
    def get_messages(self, max_messages=DEFAULT_MAX_MESSAGES_PER_REQUEST):
        """
        Method for consuming messages using Synchronous Pull
        @param max_messages: maximum number of messages to get (can return fewer messages)
        @return messages: list with content of the messages in json format
        @return ack_ids: list of the messages' acknowledgement ids
        """
        response = self._pubsub_client.request_messages(max_messages=max_messages)
        ack_ids = []
        messages = []

        for received_message in response.received_messages:
            ack_ids.append(received_message.ack_id)
            messages.append(json.loads(received_message.message.data))

        logger.info(f"m=get_messages, msg=Received {len(ack_ids)} messages.")

        return messages, ack_ids

    @logger(exclude_return=True)
    def get_messages_with_retries(self, max_retries, retry):
        """
        Method for consuming messages using Synchronous Pull with retries
        @param max_retries: maximum number of times to try pull messages.
        @return messages: list with content of the messages in json format
        @return ack_ids: list of the messages' acknowledgement ids
        """
        messages, ack_ids = self.get_messages()
        retry += 1

        # Pubsub can return 0 messages even when there are messages in subscription.
        if not messages and retry < max_retries:
            messages, ack_ids = self.get_messages_with_retries(max_retries, retry)

        return messages, ack_ids

    @logger(exclude_return=True)
    def get_messages_in_chunks(self, chunk_size, max_retries, pull_timeout=None):
        """
        Method for consuming messages in chunks
        @param chunk_size: minimum number of messages to return in each iteration.
        @param max_retries: maximum number of times to try pull messages.
        @param pull_timeout: maximum timeframe (in seconds) to pull messages.
        @return messages: list with content of the messages in json format
        @return ack_ids: list of the messages' acknowledgement ids
        """
        start_pull_time = time()

        final_messages = []
        final_ack_ids = []

        while True:
            messages, ack_ids = self.get_messages_with_retries(max_retries, 0)

            if not messages:
                logger.info(
                    f"m=get_messages_in_chunks, pubsub_consumer={self._pubsub_client}, msg=All messages have been consumed!"
                )
                break

            final_messages.extend(messages)
            final_ack_ids.extend(ack_ids)

            # Return messages and ack_ids when the chunk_size is reached.
            # Restart the pull.
            if len(final_messages) > chunk_size:
                yield final_messages, final_ack_ids
                final_messages = []
                final_ack_ids = []

            # Exit if timeout is setted and the execution time had reached it.
            if pull_timeout and (time() - start_pull_time >= pull_timeout):
                logger.info(
                    f"m=get_messages_in_chunks, pubsub_consumer={self._pubsub_client}, msg=Timeout is reached"
                )
                break

        yield final_messages, final_ack_ids
