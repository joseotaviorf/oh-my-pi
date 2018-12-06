from datetime import timedelta

from qa_python_utils.kafka.dispatcher import KafkaDispatcher


def notify_success(dispatcher=None, **kwargs):
    if dispatcher is None:
        dispatcher = KafkaDispatcher()

    partition_date = kwargs.get('execution_date') + timedelta(days=7)

    dispatcher.dispatch_message(
        topic='SkynetRecommender',
        event_name='EmbeddingsProcessingFinished',
        payload={'partitionDate': partition_date.strftime('%Y-%m-%d')},
        source='airflow')
