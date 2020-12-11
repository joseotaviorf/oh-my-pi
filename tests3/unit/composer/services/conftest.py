import pytest

from bietlejuice.jobs.composer.services.secrets_service import SecretsService


@pytest.fixture()
def secrets_service():
    return SecretsService()
