from qa_python_utils.kafka.dispatcher import KafkaDispatcher


def notify_success(dispatcher=None, **kwargs):
    if dispatcher is None:
        dispatcher = KafkaDispatcher()

    dispatcher.dispatch_message(
        topic='SkynetRecommender',
        event_name='EmbeddingsProcessingFinished',
        payload={},
        source='airflow')
