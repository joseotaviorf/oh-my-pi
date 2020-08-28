import pytest

from bietlejuice.jobs.composer.clients.service_clients.pubsub.pubsub_sync_pull_client import (
    PubSubSubscriberSyncPullClient,
)

@pytest.fixture
def pubsub_client():
    return PubSubSubscriberSyncPullClient(
        project_id="project_id",
        subscription_id="subscription_id"
    )
