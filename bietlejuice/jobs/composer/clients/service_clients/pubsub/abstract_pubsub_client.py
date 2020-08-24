from quintoandar_logger import QuintoAndarLogger
from abc import abstractmethod, ABC
from google.cloud import pubsub_v1


logger = QuintoAndarLogger("AbstractPubSubSubscriberClient")


class AbstractPubSubSubscriberClient(ABC):
    @logger
    def __init__(self, project_id, subscription_id):
        self.__project_id = project_id
        self.__subscription_id = subscription_id
        self.__session = None

    @property
    def _subscription_path(self):
        return self._client.subscription_path(self.__project_id, self.__subscription_id)

    @property
    def _client(self):
        if not self.__session:
            self.__session = pubsub_v1.SubscriberClient()
        return self.__session

    @abstractmethod
    def request_messages(self, max_messages=None):
        raise NotImplementedError()
