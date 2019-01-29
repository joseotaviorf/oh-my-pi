from datetime import datetime

from mock import MagicMock, call

from bietlejuice.jobs.dags.skynet_recommender.notify_success import notify_success


def test_notify_success_callable():
    dispatcher = MagicMock()
    notify_success(dispatcher=dispatcher, execution_date=datetime(2018, 9, 30))

    calls = [call(event_name='EmbeddingsProcessingFinished',
                  payload={'partitionDate': '2018-10-07'},
                  source='airflow',
                  topic='SkynetRecommender')]

    dispatcher.dispatch_message.assert_has_calls(calls)
