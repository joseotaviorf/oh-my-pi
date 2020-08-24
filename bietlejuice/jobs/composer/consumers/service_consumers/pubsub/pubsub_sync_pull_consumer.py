from quintoandar_logger import QuintoAndarLogger
import json

logger = QuintoAndarLogger("PubSubSubscriberSyncPullConsumer")


class PubSubSubscriberSyncPullConsumer:

    DEFAULT_MAX_MESSAGES_PER_REQUEST = 300

    @logger
    def __init__(self, pubsub_client):
        self.__pubsub_client = pubsub_client

    @logger(exclude_return=True)
    def get_messages(self, max_messages=DEFAULT_MAX_MESSAGES_PER_REQUEST):
        """
        Method for consuming messages using Synchronous Pull
        @param max_messages: maximum number of messages to get (can return fewer messages)
        @return messages: list with content of the messages in json format
        @return ack_ids: list of the messages' acknowledgement ids
        """
        response = self.__pubsub_client.request_messages(max_messages=max_messages)
        ack_ids = []
        messages = []

        for received_message in response.received_messages:
            ack_ids.append(received_message.ack_id)
            messages.append(json.loads(received_message.message.data))

        logger.info(f"m=get_messages, msg=Received {len(ack_ids)} messages.")

        return messages, ack_ids
