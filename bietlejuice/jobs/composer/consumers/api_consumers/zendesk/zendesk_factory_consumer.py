from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers.api_consumers.zendesk.zendesk_chat_consumer import (
    ZendeskChatsConsumer,
)

logger = QuintoAndarLogger("ZendeskFactoryConsumer")


class ZendeskFactoryConsumer:
    @staticmethod
    def factory(zendesk_client, spark_client, endpoint, execution_date):
        if endpoint is None:
            raise ValueError("m=factory, class_={}, msg=endpoint can't be None")
        class_ = ZendeskFactoryConsumer.__dispatch_dict(endpoint)
        if not class_:
            raise RuntimeError(
                "m=factory, endpoint={}, msg=class type for endpoint not found".format(
                    endpoint
                )
            )
        return class_(zendesk_client, spark_client, execution_date)

    @staticmethod
    def __dispatch_dict(endpoint):
        return {"chats": ZendeskChatsConsumer}.get(endpoint)
