import pytest

from bietlejuice.jobs.composer.etl.amplitude import AmplitudeEvents

@pytest.fixture()
def amplitude_events():
    return AmplitudeEvents()
