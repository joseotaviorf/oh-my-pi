from mock import MagicMock, call

from bietlejuice.jobs.dags.skynet_recommender.notify_success import notify_success


def test_notify_success_callable():
        dispatcher = MagicMock()
        notify_success(dispatcher=dispatcher)

        calls = [call(event_name='EmbeddingsProcessingFinished',
                      payload={},
                      source='airflow',
                      topic='SkynetRecommender')]

        dispatcher.dispatch_message.assert_has_calls(calls)
