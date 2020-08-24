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
        @param max_messages: maximum number of messages to get (can return fewer messages)
        @return response: PullResponse instance with the messages
        """
        response = self._client.pull(self._subscription_path, max_messages=max_messages)
        return response

    @logger(exclude=["ack_ids"])
    def acknowledge_messages(self, ack_ids):
        self._client.acknowledge(self._subscription_path, ack_ids)
        logger.info(
            f"m=acknowledge_messages, msg=Acknowledged {len(ack_ids)} messages."
        )
