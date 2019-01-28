import pytest

from bietlejuice.jobs.etl.leads.leads_reprocessor import LeadsReprocessor

config_json = """
                {
                    "query": "",
                    "defaultColumns": {"id": 1},
                    "infosExtras": ""
                }
                """


@pytest.fixture(scope='session')
def lead_reprocessor():
    return LeadsReprocessor(
        config_json=config_json
    )
