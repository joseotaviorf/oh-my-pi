from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.clients.service_clients.pubsub.abstract_pubsub_client import (
    AbstractPubSubSubscriberClient,
)

logger = QuintoAndarLogger("PubSubSubscriberSyncPullClient")


class PubSubSubscriberSyncPullClient(AbstractPubSubSubscriberClient):
    @logger
    def __init__(self, project_id, subscription_id):
        super().__init__(project_id=project_id, subscription_id=subscription_id)

    @logger(exclude_return=True)
    def request_messages(self, max_messages):
        """
        Method for requesting messages in a specified subscription using Synchronous Pull
        @param max_messages: maximum number of messages to get (can return fewer messages).
        It must be a value between 1 and 1000, a GCP limitation.
        @return response: PullResponse instance with the messages
        """
        self.__validate_max_messages(max_messages)

        response = self._client.pull(self._subscription_path, max_messages=max_messages)

        return response

    def __validate_max_messages(self, max_messages):
        self.__check_type_max_messages(max_messages)
        self.__check_range_max_messages(max_messages)

    def __check_type_max_messages(self, max_messages):
        if not isinstance(max_messages, int):
            raise TypeError(
                f"m=request_messages, msg=max_messages must be an integer and not {type(max_messages)} type"
            )

    def __check_range_max_messages(self, max_messages):
        if not (0 < max_messages < 1001):
            raise ValueError(
                "m=request_messages, msg=max_messages must be a value between 1 and 1000"
            )

    @logger(exclude=["ack_ids"])
    def acknowledge_messages(self, ack_ids):
        self.__validate_ack_ids(ack_ids)

        self._client.acknowledge(self._subscription_path, ack_ids)
        logger.info(
            f"m=acknowledge_messages, msg=Acknowledged {len(ack_ids)} messages."
        )

    def __validate_ack_ids(self, ack_ids):
        self.__check_type_ack_ids(ack_ids)
        self.__check_empty_ack_ids(ack_ids)

    def __check_type_ack_ids(self, ack_ids):
        if not isinstance(ack_ids, list):
            raise TypeError(
                f"m=acknowledge_messages, msg=ack_ids must be a list and not {type(ack_ids)} type"
            )

    def __check_empty_ack_ids(self, ack_ids):
        if len(ack_ids) == 0:
            raise ValueError(
                "m=acknowledge_messages, msg=ack_ids cannot be an empty list"
            )
