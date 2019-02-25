import pytest

from bietlejuice.jobs.etl.leads import LeadsReprocessor, LeadsProcessor

config_json = """
                {
                    "query": "",
                    "defaultColumns": {"id": 1},
                    "infosExtras": ""
                }
                """


@pytest.fixture(scope='session')
def leads_reprocessor():
    return LeadsReprocessor(
        config_json=config_json
    )


@pytest.fixture(scope='session')
def leads_processor():
    return LeadsProcessor()
