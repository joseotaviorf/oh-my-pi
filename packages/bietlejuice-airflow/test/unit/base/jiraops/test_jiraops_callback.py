import datetime
import json
from unittest.mock import MagicMock, patch

import pendulum
import pytest

from bietlejuice.base.airflow.enums.dag_run_type_enum import DagRunTypeEnum
from bietlejuice.base.incident_context_enrichers.enricher import IncidentContextEnricher

FAKE_TIME = datetime.datetime(2025, 5, 5, 12, 0, 0)


@pytest.fixture
def patch_datetime_now(monkeypatch):
    class fake_datetime(datetime.datetime):
        @classmethod
        def now(cls, tz=None):
            return FAKE_TIME

    monkeypatch.setattr(datetime, "datetime", fake_datetime)


def get_mock_variable(key):
    if key == "environment":
        return "prod"
    elif key == "JIRA_OPS_ONCALL_APIKEY":
        return json.dumps(
            {
                "username": "test_username",
                "token": "test_token",
                "cloud_id": "test_cloud_id",
            }
        )
    return None


@pytest.fixture
def mock_airflow_variables():
    mock_variable = MagicMock()
    mock_variable.get.side_effect = get_mock_variable
    return mock_variable


@pytest.fixture
def mock_jiraops_client():
    """Patch JiraOpsClient where the callback uses it so the mock is used at runtime."""
    with patch(
        "bietlejuice.base.jiraops.jiraops_callback.JiraOpsClient"
    ) as mock_client_class:
        mock_client_instance = MagicMock()
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"result": "success"}
        mock_client_instance.create_alert.return_value = mock_response
        mock_client_class.return_value = mock_client_instance
        yield mock_client_class, mock_client_instance


class DummyEnricher(IncidentContextEnricher):
    """Dummy enricher for tests: adds DummyKey to extra_properties and suffix to description."""

    def enrich(self, context, extra_properties, description):
        extra_properties = dict(extra_properties)
        extra_properties["DummyKey"] = "dummy_value"
        return extra_properties, description + "\n[Dummy enricher]"


class DatabricksStyleDummyEnricher(IncidentContextEnricher):
    """Dummy enricher that adds Databricks-like keys for tests."""

    def enrich(self, context, extra_properties, description):
        extra_properties = dict(extra_properties)
        extra_properties["DatabricksError"] = "SparkException: OOM"
        extra_properties["DatabricksRunURL"] = "https://dbc/runs/123"
        extra_properties["ClusterLogLocation"] = "s3://logs/cluster-abc"
        description += "\nError: SparkException: OOM"
        description += "\nRun URL: https://dbc/runs/123"
        description += "\nCluster Logs: s3://logs/cluster-abc"
        return extra_properties, description


def mock_context():
    dataset_alias = MagicMock()
    dataset_alias.name = "dag:task:alias"
    task_instance = MagicMock()
    task_instance.xcom_pull.return_value = None
    task = MagicMock()
    task_instance.task = task
    task.task_id = "test_task"
    task.owner = "testOwner"
    dag = MagicMock()
    dag.dag_id = "test_dag"
    outlet_event_accessor = MagicMock()
    task_instance.task_id = task.task_id = "test_task"
    task_instance.dag_id = "test_dag"
    task_instance.start_date = pendulum.datetime(2025, 1, 2)
    dag_run = MagicMock()
    dag_run.run_id = "manual__2025-01-01T00:00:00+00:00"
    dag_run.run_type = "manual"
    task_instance.dag_run = dag_run

    return {
        "params": {"run_type": "test_run"},
        "outlets": [dataset_alias],
        "outlet_events": {"dag:task:alias": outlet_event_accessor},
        "triggering_dataset_events": {},
        "execution_date": pendulum.datetime(2025, 1, 1),
        "ti": task_instance,
        "task": task,
        "dag_run": dag_run,
        "dag": dag,
        "task_instance": task_instance,
    }


@pytest.fixture
def jiraops_callback(mock_airflow_variables, patch_datetime_now):
    """Patch Variable and datetime at use-site so we never invoke real Airflow."""

    class fake_datetime(datetime.datetime):
        @classmethod
        def now(cls, tz=None):
            return FAKE_TIME

    with (
        patch(
            "bietlejuice.base.jiraops.jiraops_callback.Variable",
            mock_airflow_variables,
        ),
        patch(
            "bietlejuice.base.jiraops.jiraops_callback.datetime",
            fake_datetime,
        ),
    ):
        from bietlejuice.base.jiraops.jiraops_callback import JiraOpsCallback

        yield JiraOpsCallback()


@pytest.fixture
def jiraops_callback_with_config(mock_airflow_variables, patch_datetime_now):
    """Patch Variable and datetime at use-site so we never invoke real Airflow."""

    class fake_datetime(datetime.datetime):
        @classmethod
        def now(cls, tz=None):
            return FAKE_TIME

    with (
        patch(
            "bietlejuice.base.jiraops.jiraops_callback.Variable",
            mock_airflow_variables,
        ),
        patch(
            "bietlejuice.base.jiraops.jiraops_callback.datetime",
            fake_datetime,
        ),
    ):
        from bietlejuice.base.jiraops.jiraops_callback import JiraOpsCallback

        yield JiraOpsCallback(
            dag_args={"jiraops_responder_team_id": "og-mlops-team-id"},
            cluster_args={"databricks_conn_id": "test_databricks_conn"},
        )


@pytest.fixture
def jiraops_databricks_callback(mock_airflow_variables, patch_datetime_now):
    """Callback with Databricks-style enricher for tests."""

    class fake_datetime(datetime.datetime):
        @classmethod
        def now(cls, tz=None):
            return FAKE_TIME

    with (
        patch(
            "bietlejuice.base.jiraops.jiraops_callback.Variable",
            mock_airflow_variables,
        ),
        patch(
            "bietlejuice.base.jiraops.jiraops_callback.datetime",
            fake_datetime,
        ),
    ):
        from bietlejuice.base.jiraops.jiraops_callback import JiraOpsCallback

        yield JiraOpsCallback().add_context_enricher(DatabricksStyleDummyEnricher())


@patch("bietlejuice.services.dataset_service.DatasetService._get_run_type")
def test_task_failure_alert_prod_environment(
    mock_get_run_type, mock_airflow_variables, mock_jiraops_client, jiraops_callback
):
    mock_get_run_type.return_value = DagRunTypeEnum.IMPACT_DOWNSTREAM_DEPENDENTS

    mock_client_class, mock_client_instance = mock_jiraops_client
    context = mock_context()

    jiraops_callback.task_failure_alert(context)

    mock_get_run_type.assert_called_once_with(context)

    mock_airflow_variables.get.assert_any_call("environment")
    mock_airflow_variables.get.assert_any_call("JIRA_OPS_ONCALL_APIKEY")

    expected_credentials = {
        "username": "test_username",
        "token": "test_token",
        "cloud_id": "test_cloud_id",
    }
    mock_client_class.assert_called_once_with(expected_credentials)

    expected_message = "DAG: test_dag - Task: test_task"
    expected_description = "DAG: test_dag - Task: test_task at: 2025-05-05 12:00:00"
    expected_tags = ["test_dag", "test_task", "task failed"]

    expected_extra_properties = {
        "DAG": "test_dag",
        "TaskPath": "test_dag:test_task",
        "Task": "test_task",
        "DAGOwner": "testOwner",
        "Criticality": "Medium",
    }

    mock_client_instance.create_alert.assert_called_once_with(
        message=expected_message,
        description=expected_description,
        tags=expected_tags,
        extra_properties=expected_extra_properties,
        responder_team_id=None,
        priority="P3",
    )


@patch("bietlejuice.services.dataset_service.DatasetService._get_run_type")
def test_task_failure_alert_uses_declared_task_criticality(
    mock_get_run_type, mock_airflow_variables, mock_jiraops_client, jiraops_callback
):
    mock_get_run_type.return_value = DagRunTypeEnum.IMPACT_DOWNSTREAM_DEPENDENTS
    mock_client_class, mock_client_instance = mock_jiraops_client
    context = mock_context()
    context["params"]["criticality"] = "Critical"

    jiraops_callback.task_failure_alert(context)

    mock_client_instance.create_alert.assert_called_once()
    _, kwargs = mock_client_instance.create_alert.call_args
    assert kwargs["priority"] == "P1"
    assert kwargs["extra_properties"]["Criticality"] == "Critical"


@patch("bietlejuice.services.dataset_service.DatasetService._get_run_type")
def test_task_failure_alert_tags_table_owner_when_declared(
    mock_get_run_type, mock_airflow_variables, mock_jiraops_client, jiraops_callback
):
    mock_get_run_type.return_value = DagRunTypeEnum.IMPACT_DOWNSTREAM_DEPENDENTS
    mock_client_class, mock_client_instance = mock_jiraops_client
    context = mock_context()
    context["params"]["owner"] = "table-owner@quintoandar.com.br"

    jiraops_callback.task_failure_alert(context)

    mock_client_instance.create_alert.assert_called_once()
    _, kwargs = mock_client_instance.create_alert.call_args
    assert kwargs["extra_properties"]["TableOwner"] == "table-owner@quintoandar.com.br"


@patch("bietlejuice.services.dataset_service.DatasetService._get_run_type")
def test_task_failure_alert_omits_table_owner_when_undeclared(
    mock_get_run_type, mock_airflow_variables, mock_jiraops_client, jiraops_callback
):
    mock_get_run_type.return_value = DagRunTypeEnum.IMPACT_DOWNSTREAM_DEPENDENTS
    mock_client_class, mock_client_instance = mock_jiraops_client
    context = mock_context()

    jiraops_callback.task_failure_alert(context)

    mock_client_instance.create_alert.assert_called_once()
    _, kwargs = mock_client_instance.create_alert.call_args
    assert "TableOwner" not in kwargs["extra_properties"]


@patch("bietlejuice.services.dataset_service.DatasetService._get_run_type")
def test_dag_failure_alert_uses_dag_criticality(
    mock_get_run_type, mock_airflow_variables, mock_jiraops_client, jiraops_callback
):
    from bietlejuice.base.jiraops.jiraops_callback import JiraOpsCallback

    mock_get_run_type.return_value = DagRunTypeEnum.IMPACT_DOWNSTREAM_DEPENDENTS
    mock_client_class, mock_client_instance = mock_jiraops_client
    context = mock_context()
    context["params"] = {}

    callback = JiraOpsCallback(dag_args={"criticality": "High"})
    callback.dag_failure_alert(context)

    mock_client_instance.create_alert.assert_called_once()
    _, kwargs = mock_client_instance.create_alert.call_args
    assert kwargs["priority"] == "P2"
    assert kwargs["extra_properties"]["Criticality"] == "High"


@patch("bietlejuice.services.dataset_service.DatasetService._get_run_type")
def test_task_failure_alert_test_run_skips_alert(
    mock_get_run_type, mock_airflow_variables, mock_jiraops_client, jiraops_callback
):
    mock_get_run_type.return_value = DagRunTypeEnum.TEST_RUN

    mock_client_class, mock_client_instance = mock_jiraops_client
    context = mock_context()

    jiraops_callback.task_failure_alert(context)

    mock_get_run_type.assert_called_once_with(context)
    mock_airflow_variables.get.assert_any_call("environment")

    mock_client_class.assert_not_called()
    mock_client_instance.create_alert.assert_not_called()


@patch("bietlejuice.services.dataset_service.DatasetService._get_run_type")
def test_task_failure_alert_non_prod_environment_skips_alert(
    mock_get_run_type, mock_airflow_variables, mock_jiraops_client, jiraops_callback
):
    mock_get_run_type.return_value = DagRunTypeEnum.IMPACT_DOWNSTREAM_DEPENDENTS

    def get_mock_variable_non_prod(key):
        if key == "environment":
            return "forno"
        elif key == "JIRA_OPS_ONCALL_APIKEY":
            return json.dumps(
                {
                    "username": "test_username",
                    "token": "test_token",
                    "cloud_id": "test_cloud_id",
                }
            )
        return None

    mock_airflow_variables.get.side_effect = get_mock_variable_non_prod

    mock_client_class, mock_client_instance = mock_jiraops_client
    context = mock_context()

    jiraops_callback.task_failure_alert(context)

    mock_get_run_type.assert_called_once_with(context)
    mock_airflow_variables.get.assert_any_call("environment")

    mock_client_class.assert_not_called()
    mock_client_instance.create_alert.assert_not_called()


@patch("bietlejuice.services.dataset_service.DatasetService._get_run_type")
def test_alert_includes_databricks_context_when_available(
    mock_get_run_type,
    mock_airflow_variables,
    mock_jiraops_client,
    jiraops_databricks_callback,
):
    mock_get_run_type.return_value = DagRunTypeEnum.IMPACT_DOWNSTREAM_DEPENDENTS
    mock_client_class, mock_client_instance = mock_jiraops_client
    context = mock_context()

    jiraops_databricks_callback.task_failure_alert(context)

    _, kwargs = mock_client_instance.create_alert.call_args
    assert kwargs["extra_properties"]["DatabricksError"] == "SparkException: OOM"
    assert kwargs["extra_properties"]["DatabricksRunURL"] == "https://dbc/runs/123"
    assert kwargs["extra_properties"]["ClusterLogLocation"] == "s3://logs/cluster-abc"
    assert "SparkException: OOM" in kwargs["description"]
    assert "https://dbc/runs/123" in kwargs["description"]
    assert "s3://logs/cluster-abc" in kwargs["description"]


@patch("bietlejuice.services.dataset_service.DatasetService._get_run_type")
def test_alert_sent_without_enrichment_when_databricks_context_fails(
    mock_get_run_type,
    mock_airflow_variables,
    mock_jiraops_client,
    jiraops_databricks_callback,
):
    mock_get_run_type.return_value = DagRunTypeEnum.IMPACT_DOWNSTREAM_DEPENDENTS
    mock_client_class, mock_client_instance = mock_jiraops_client
    context = mock_context()

    enricher = jiraops_databricks_callback._context_enrichers[0]
    with patch.object(
        enricher,
        "enrich",
        side_effect=lambda c, e, d: (e, d),
    ):
        jiraops_databricks_callback.task_failure_alert(context)

    mock_client_instance.create_alert.assert_called_once()
    _, kwargs = mock_client_instance.create_alert.call_args
    assert "DatabricksError" not in kwargs["extra_properties"]
    assert "DatabricksRunURL" not in kwargs["extra_properties"]
    assert "ClusterLogLocation" not in kwargs["extra_properties"]


@patch("bietlejuice.services.dataset_service.DatasetService._get_run_type")
def test_custom_responder_team_id_passed_to_client(
    mock_get_run_type,
    mock_airflow_variables,
    mock_jiraops_client,
    jiraops_callback_with_config,
):
    mock_get_run_type.return_value = DagRunTypeEnum.IMPACT_DOWNSTREAM_DEPENDENTS
    mock_client_class, mock_client_instance = mock_jiraops_client
    context = mock_context()

    jiraops_callback_with_config.task_failure_alert(context)

    _, kwargs = mock_client_instance.create_alert.call_args
    assert kwargs["responder_team_id"] == "og-mlops-team-id"


@patch("bietlejuice.services.dataset_service.DatasetService._get_run_type")
def test_default_responder_team_id_is_none_when_no_dag_args(
    mock_get_run_type,
    mock_airflow_variables,
    mock_jiraops_client,
    jiraops_callback,
):
    mock_get_run_type.return_value = DagRunTypeEnum.IMPACT_DOWNSTREAM_DEPENDENTS
    mock_client_class, mock_client_instance = mock_jiraops_client
    context = mock_context()

    jiraops_callback.task_failure_alert(context)

    _, kwargs = mock_client_instance.create_alert.call_args
    assert kwargs["responder_team_id"] is None


@patch("bietlejuice.services.dataset_service.DatasetService._get_run_type")
def test_alert_includes_dummy_enricher_context_when_enricher_added(
    mock_get_run_type,
    mock_airflow_variables,
    mock_jiraops_client,
    jiraops_callback,
):
    mock_get_run_type.return_value = DagRunTypeEnum.IMPACT_DOWNSTREAM_DEPENDENTS
    mock_client_class, mock_client_instance = mock_jiraops_client
    context = mock_context()

    jiraops_callback.add_context_enricher(DummyEnricher()).task_failure_alert(context)

    mock_client_instance.create_alert.assert_called_once()
    _, kwargs = mock_client_instance.create_alert.call_args
    assert kwargs["extra_properties"]["DummyKey"] == "dummy_value"
    assert "[Dummy enricher]" in kwargs["description"]


@patch("bietlejuice.services.dataset_service.DatasetService._get_run_type")
def test_add_context_enricher_returns_self_for_chaining(
    mock_get_run_type,
    mock_airflow_variables,
    mock_jiraops_client,
    jiraops_callback,
):
    result = jiraops_callback.add_context_enricher(DummyEnricher())
    assert result is jiraops_callback
    result.add_context_enricher(DummyEnricher())
    assert len(jiraops_callback._context_enrichers) == 2


@patch("bietlejuice.services.dataset_service.DatasetService._get_run_type")
def test_enricher_that_raises_does_not_break_alert(
    mock_get_run_type,
    mock_airflow_variables,
    mock_jiraops_client,
    jiraops_callback,
):
    class FailingEnricher(IncidentContextEnricher):
        def enrich(self, context, extra_properties, description):
            raise ValueError("enricher failed")

    mock_get_run_type.return_value = DagRunTypeEnum.IMPACT_DOWNSTREAM_DEPENDENTS
    mock_client_class, mock_client_instance = mock_jiraops_client
    context = mock_context()

    jiraops_callback.add_context_enricher(FailingEnricher()).task_failure_alert(context)

    mock_client_instance.create_alert.assert_called_once()
    _, kwargs = mock_client_instance.create_alert.call_args
    assert "DAG" in kwargs["extra_properties"]
    assert "Task" in kwargs["extra_properties"]
    assert "DummyKey" not in kwargs["extra_properties"]


@patch("bietlejuice.services.dataset_service.DatasetService._get_run_type")
def test_dag_failure_alert_creates_alert_without_task_id(
    mock_get_run_type,
    mock_airflow_variables,
    mock_jiraops_client,
    jiraops_callback,
):
    """DAG-level failure alert has no task_id in message, tags, or extra_properties."""
    mock_get_run_type.return_value = DagRunTypeEnum.IMPACT_DOWNSTREAM_DEPENDENTS
    mock_client_class, mock_client_instance = mock_jiraops_client
    context = mock_context()

    jiraops_callback.dag_failure_alert(context)

    mock_client_instance.create_alert.assert_called_once()
    _, kwargs = mock_client_instance.create_alert.call_args
    assert kwargs["message"] == "DAG: test_dag Failed"
    assert "test_task" not in kwargs["message"]
    assert kwargs["tags"] == ["test_dag", "dag failed"]
    assert "Task" not in kwargs["extra_properties"]
    assert kwargs["extra_properties"]["DAG"] == "test_dag"


def test_add_context_enricher_ignores_non_enricher(jiraops_callback):
    """Passing a non-IncidentContextEnricher does not add it to _context_enrichers."""
    result = jiraops_callback.add_context_enricher("not an enricher")
    assert result is jiraops_callback
    assert len(jiraops_callback._context_enrichers) == 0

    result = jiraops_callback.add_context_enricher(None)
    assert len(jiraops_callback._context_enrichers) == 0


@patch("bietlejuice.services.dataset_service.DatasetService._get_run_type")
def test_multiple_enrichers_run_in_order_and_chain_output(
    mock_get_run_type,
    mock_airflow_variables,
    mock_jiraops_client,
    jiraops_callback,
):
    """Enrichers run in order; second enricher receives first enricher's output."""

    class FirstEnricher(IncidentContextEnricher):
        def enrich(self, context, extra_properties, description):
            extra_properties = dict(extra_properties)
            extra_properties["First"] = "1"
            return extra_properties, description + "\nFirst"

    class SecondEnricher(IncidentContextEnricher):
        def enrich(self, context, extra_properties, description):
            extra_properties = dict(extra_properties)
            assert "First" in extra_properties, (
                "Second enricher should see First enricher output"
            )
            extra_properties["Second"] = "2"
            return extra_properties, description + "\nSecond"

    mock_get_run_type.return_value = DagRunTypeEnum.IMPACT_DOWNSTREAM_DEPENDENTS
    mock_client_class, mock_client_instance = mock_jiraops_client
    context = mock_context()

    jiraops_callback.add_context_enricher(FirstEnricher()).add_context_enricher(
        SecondEnricher()
    ).task_failure_alert(context)

    mock_client_instance.create_alert.assert_called_once()
    _, kwargs = mock_client_instance.create_alert.call_args
    assert kwargs["extra_properties"]["First"] == "1"
    assert kwargs["extra_properties"]["Second"] == "2"
    assert "\nFirst" in kwargs["description"]
    assert "\nSecond" in kwargs["description"]
