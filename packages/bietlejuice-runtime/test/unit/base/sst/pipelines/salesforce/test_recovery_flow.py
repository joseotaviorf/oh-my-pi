"""Unit tests for the Salesforce CDC recovery pipeline."""

from unittest import mock

import pytest

from bietlejuice.base.sst.pipelines.salesforce import recovery_flow

API_ENTITY = "CaseLegalOps__c"
DAG_NAME = "salesforce_for_sale"
JOB_NAME = "load_datalake_salesforce_raw_events_case_legal_ops"
TARGET_SCHEMA = "datalake_salesforce_raw"
TARGET_TABLE = "events_case_legal_ops"
PARTITION_DATE = "2026-09-09"
PARTITION_HOUR = "16"


def _recover(salesforce_endpoint):
    return recovery_flow.events_case_recovery(
        spark=mock.MagicMock(),
        api_entity=API_ENTITY,
        salesforce_endpoint=salesforce_endpoint,
        dag_name=DAG_NAME,
        job_name=JOB_NAME,
        target_schema=TARGET_SCHEMA,
        target_table=TARGET_TABLE,
        env="forno",
        partition_date=PARTITION_DATE,
        partition_hour=PARTITION_HOUR,
    )


class TestEventsCaseRecoveryEndpointGuard:
    @pytest.mark.parametrize("endpoint", [None, ""])
    def test_missing_endpoint_raises_value_error(self, endpoint):
        """A DAG that never forwards --salesforce_endpoint must fail readably.

        Regression: rstrip ran before retrieve_token's own check, so the failure
        surfaced as ``'NoneType' object has no attribute 'rstrip'``.
        """
        with pytest.raises(ValueError, match="salesforce_endpoint is required"):
            _recover(endpoint)

    @pytest.mark.parametrize("endpoint", [None, ""])
    def test_missing_endpoint_does_not_call_salesforce(self, endpoint):
        with mock.patch.object(recovery_flow, "retrieve_token") as retrieve_token:
            with pytest.raises(ValueError):
                _recover(endpoint)
        retrieve_token.assert_not_called()

    def test_error_names_the_target_table(self):
        with pytest.raises(ValueError, match=f"{TARGET_SCHEMA}.{TARGET_TABLE}"):
            _recover(None)
