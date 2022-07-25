import mock
import pytest

from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)


@pytest.fixture
@mock.patch.object(ConfigurationService, "_load_configurations_from_files")
@mock.patch.object(ConfigurationService, "_get_configuration_files")
@mock.patch.object(ConfigurationService, "_get_environment")
def configuration_service(
    mock__get_environment,
    mock__get_configuration_files,
    mock__load_configurations_from_files,
):
    configuration_service = ConfigurationService()

    return configuration_service
