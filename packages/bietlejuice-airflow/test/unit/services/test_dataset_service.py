import datetime
import json
from unittest import mock

import pendulum
import pytest
from airflow.datasets import BaseDataset, Dataset, DatasetAll, DatasetAny
from airflow.exceptions import AirflowException

from bietlejuice.services.dataset_service import DatasetService

FAKE_TIME = datetime.datetime(2025, 1, 1, 0, 0, 0)  # Fixed time for testing purposes


class TestDatasetService:
    @pytest.fixture(autouse=True)
    def patch_datetime_now(self):
        class fake_datetime(datetime.datetime):
            @classmethod
            def now(cls):
                return FAKE_TIME

        with mock.patch("bietlejuice.services.dataset_service.datetime", fake_datetime):
            yield

    def test_get_dag_datasets_from_dependencies_should_return_none_if_no_dependencies(
        self,
    ):
        dependencies = []

        result = DatasetService.get_dag_datasets_from_dependencies(dependencies)

        assert result is None

    def test_get_dag_datasets_from_dependencies_should_structure_dataset_object_correctly(
        self,
    ):
        dependencies = ["dag1:task1", "dag1:task2", "dag2:task1"]

        result = DatasetService.get_dag_datasets_from_dependencies(dependencies)

        assert result is not None
        assert dataset_equals(
            result,  # We trigger a DAG when one of two conditions is met:
            (  # 1 - All dependencies have executed since the DAG last ran
                Dataset("dag1:task1") & Dataset("dag1:task2") & Dataset("dag2:task1")
            )
            | (  # 2 - Any of the dependencies was reprocessed
                Dataset("dag1:task1:reprocessing")
                | Dataset("dag1:task2:reprocessing")
                | Dataset("dag2:task1:reprocessing")
            ),
        )

    def test_get_dag_datasets_from_dependencies_should_accept_custom_dict_expressions(
        self,
    ):
        dependencies = {"any": [{"all": ["dag1:task1", "dag2:task1"]}, "dag1:task2"]}
        result = DatasetService.get_dag_datasets_from_dependencies(dependencies)
        assert result is not None

        assert dataset_equals(
            result,
            (  # 1 - Custom dict expression
                (Dataset("dag1:task1") & Dataset("dag2:task1")) | Dataset("dag1:task2")
            )
            | (  # 2 - Any of the dependencies was reprocessed
                Dataset("dag1:task1:reprocessing")
                | Dataset("dag1:task2:reprocessing")
                | Dataset("dag2:task1:reprocessing")
            ),
        )

    def test_get_dag_datasets_from_dependencies_should_remove_redundant_dependencies_from_reprocessing(
        self,
    ):
        dependencies = {"any": [{"all": ["dag1:task1", "dag2:task1"]}, "dag1:task2"]}
        redundant_dependencies = ["dag1:task1"]
        result = DatasetService.get_dag_datasets_from_dependencies(
            dependencies, redundant_dependencies
        )
        assert result is not None

        assert dataset_equals(
            result,
            (  # 1 - Custom dict expression
                (Dataset("dag1:task1") & Dataset("dag2:task1")) | Dataset("dag1:task2")
            )
            | (  # 2 - Any of the dependencies was reprocessed, excluding redundant ones
                Dataset("dag1:task2:reprocessing") | Dataset("dag2:task1:reprocessing")
            ),
        )

    def test_get_dag_datasets_from_dependencies_should_treat_first_run_of_day_suffix_correctly(
        self,
    ):
        dependencies = {
            "any": [
                {"all": ["dag1:task1", "dag2:task1:first-run-of-day"]},
                "dag1:task2",
            ]
        }
        redundant_dependencies = ["dag1:task1"]
        result = DatasetService.get_dag_datasets_from_dependencies(
            dependencies, redundant_dependencies
        )
        assert result is not None

        assert dataset_equals(
            result,
            (  # 1 - Custom dict expression
                (Dataset("dag1:task1") & Dataset("dag2:task1:first-run-of-day"))
                | Dataset("dag1:task2")
            )
            | (  # 2 - Any of the dependencies was reprocessed, excluding redundant ones
                Dataset("dag1:task2:reprocessing") | Dataset("dag2:task1:reprocessing")
            ),
        )

    @pytest.fixture
    def mock_context(self):
        dataset_alias = mock.MagicMock()
        dataset_alias.name = "dag:task:alias"
        task_instance = mock.MagicMock()
        task_instance.xcom_pull.return_value = None
        task = mock.MagicMock()
        task_instance.task = task
        task.task_id = "task"
        dag = mock.MagicMock()
        dag.dag_id = "dag"
        outlet_event_accessor = mock.MagicMock()
        task_instance.task_id = task.task_id = "task"
        task_instance.start_date = pendulum.datetime(2025, 1, 2)
        dag_run = mock.MagicMock()
        dag_run.run_id = "dag_run_id"
        task_instance.dag_run = dag_run

        return {
            "params": {
                "run_type": "impact_downstream_dependents",
                "schema": "ebdb_contract",
                "table_name": "contract",
                "layer": "enrich",
            },
            "outlets": [dataset_alias],
            "outlet_events": {"dag:task:alias": outlet_event_accessor},
            "triggering_dataset_events": {},
            "execution_date": pendulum.datetime(2025, 1, 1),
            "ti": task_instance,
            "task": task,
            "dag_run": dag_run,
            "dag": dag,
        }

    @pytest.fixture(autouse=True)
    def mock_create_session(self):
        """
        Mock the create_session method to avoid database interactions.
        """
        session = mock.MagicMock()
        query = mock.MagicMock()
        filter = mock.MagicMock()
        session.__enter__.return_value = session
        session.query.return_value = query
        query.filter.return_value = filter
        filter.first.return_value = None
        with mock.patch(
            "bietlejuice.services.dataset_service.create_session", return_value=session
        ) as mock_create_session_func:
            yield mock_create_session_func

    @pytest.fixture()
    def database_query_function(self, mock_create_session):
        """
        Mock the database query function to avoid actual database calls.
        """
        return mock_create_session.return_value.query.return_value.filter.return_value.first

    @pytest.fixture
    def mock_is_first_run_of_date(self):
        """
        Mocka DatasetService._is_first_run_of_date e retorna o objeto mock.
        Por padrão, ele retorna True (simulando a primeira execução).
        """
        with mock.patch(
            "bietlejuice.services.dataset_service.DatasetService._is_first_run_of_date"
        ) as _mock:
            _mock.return_value = True  # Valor padrão para a maioria dos testes
            yield _mock

    def test_update_datasets_should_do_nothing_if_is_test_run(
        self, mock_is_first_run_of_date, mock_context
    ):
        mock_is_first_run_of_date.return_value = True
        mock_context["params"]["run_type"] = "test_run"

        DatasetService.update_datasets(mock_context)

        mock_context["outlet_events"]["dag:task:alias"].add.assert_not_called()

    def test_update_datasets_should_add_normal_dataset_by_default(
        self, mock_is_first_run_of_date, mock_context
    ):
        mock_is_first_run_of_date.return_value = True
        DatasetService.update_datasets(mock_context)

        mock_context["outlet_events"]["dag:task:alias"].add.assert_has_calls(
            [
                mock.call(Dataset("dag:task")),
                mock.call(Dataset("datalake_ebdb_contract.contract")),
                mock.call(Dataset("dag:task:first-run-of-day")),
                mock.call(Dataset("datalake_ebdb_contract.contract:first-run-of-day")),
            ],
            any_order=True,
        )

    def test_update_datasets_should_add_reprocessing_dataset_if_is_reprocessing_run(
        self, mock_is_first_run_of_date, mock_context
    ):
        mock_is_first_run_of_date.return_value = True
        mock_context["params"]["run_type"] = "reprocessing_run"
        DatasetService.update_datasets(mock_context)

        expected_extra = {
            "reprocessing_source": "dag",
            "reprocessing_date": FAKE_TIME.date().isoformat(),
        }
        mock_context["outlet_events"]["dag:task:alias"].add.assert_has_calls(
            [
                mock.call(Dataset("dag:task:reprocessing"), extra=expected_extra),
                mock.call(
                    Dataset("datalake_ebdb_contract.contract:reprocessing"),
                    extra=expected_extra,
                ),
            ],
            any_order=True,
        )

    def test_update_datasets_should_add_reprocessing_dataset_if_triggering_dataset_is_reprocessing(
        self, mock_is_first_run_of_date, mock_context
    ):
        mock_is_first_run_of_date.return_value = True
        dataset_event = mock.MagicMock()
        dataset_event.extra = {
            "reprocessing_source": "dag2",
            "reprocessing_date": FAKE_TIME.date().isoformat(),
        }
        mock_context["triggering_dataset_events"] = {
            "dag2:task:reprocessing": [dataset_event]
        }
        DatasetService.update_datasets(mock_context)

        expected_extra = {
            "reprocessing_source": "dag2",
            "reprocessing_date": FAKE_TIME.date().isoformat(),
        }
        mock_context["outlet_events"]["dag:task:alias"].add.assert_has_calls(
            [
                mock.call(Dataset("dag:task:reprocessing"), extra=expected_extra),
                mock.call(
                    Dataset("datalake_ebdb_contract.contract:reprocessing"),
                    extra=expected_extra,
                ),
            ],
            any_order=True,
        )

    def test_update_datasets_should_add_normal_dataset_if_triggering_dataset_is_not_reprocessing(
        self, mock_is_first_run_of_date, mock_context
    ):
        mock_is_first_run_of_date.return_value = True
        mock_context["triggering_dataset_events"] = {"dag2:task": mock.MagicMock()}
        DatasetService.update_datasets(mock_context)

        mock_context["outlet_events"]["dag:task:alias"].add.assert_has_calls(
            [
                mock.call(Dataset("dag:task")),
                mock.call(Dataset("datalake_ebdb_contract.contract")),
                mock.call(Dataset("dag:task:first-run-of-day")),
                mock.call(Dataset("datalake_ebdb_contract.contract:first-run-of-day")),
            ],
            any_order=True,
        )

    def test_first_run_of_day_dataset(self, mock_is_first_run_of_date, mock_context):
        mock_is_first_run_of_date.return_value = True
        DatasetService.update_datasets(mock_context)

        mock_context["outlet_events"]["dag:task:alias"].add.assert_has_calls(
            [
                mock.call(Dataset("dag:task")),
                mock.call(Dataset("datalake_ebdb_contract.contract")),
                mock.call(Dataset("dag:task:first-run-of-day")),
                mock.call(Dataset("datalake_ebdb_contract.contract:first-run-of-day")),
            ],
            any_order=True,
        )

    def test_if_last_execution_date_is_equal_to_date_do_not_add_first_run_of_day_dataset(
        self, mock_is_first_run_of_date, mock_context
    ):
        mock_is_first_run_of_date.return_value = False

        DatasetService.update_datasets(mock_context)

        mock_context["outlet_events"]["dag:task:alias"].add.assert_has_calls(
            [
                mock.call(Dataset("dag:task")),
                mock.call(Dataset("datalake_ebdb_contract.contract")),
            ],
            any_order=True,
        )
        first_run_calls = [
            c
            for c in mock_context["outlet_events"]["dag:task:alias"].add.call_args_list
            if "first-run-of-day" in str(c)
        ]
        assert len(first_run_calls) == 0

    @mock.patch(
        "bietlejuice.services.dataset_service.DatasetService._has_updated_dataset_before"
    )
    def test_if_it_is_a_rerun_it_should_not_update_datasets(
        self, mock_has_updated, mock_is_first_run_of_date, mock_context
    ):
        # Patch to avoid real Airflow session/DB (which triggers broken model loading in CI)
        mock_has_updated.return_value = True
        mock_is_first_run_of_date.return_value = False

        DatasetService.update_datasets(mock_context)

        mock_context["outlet_events"]["dag:task:alias"].add.assert_not_called()

    def test_should_not_trigger_reprocessing_if_event_from_a_previous_date(
        self, mock_is_first_run_of_date, mock_context
    ):
        mock_is_first_run_of_date.return_value = False
        dataset_event = mock.MagicMock()
        dataset_event.extra = {
            "reprocessing_source": "dag2",
            "reprocessing_date": (
                FAKE_TIME.date() - datetime.timedelta(days=1)
            ).isoformat(),
        }
        mock_context["triggering_dataset_events"] = {
            "dag2:task:reprocessing": [dataset_event]
        }
        DatasetService.update_datasets(mock_context)
        mock_context["outlet_events"]["dag:task:alias"].add.assert_not_called()

    @mock.patch("bietlejuice.services.dataset_service.boto3")
    @mock.patch("bietlejuice.services.dataset_service.Variable.get")
    def test_update_datasets_should_not_call_s3_when_bucket_variable_unset(
        self, mock_variable_get, mock_boto3, mock_is_first_run_of_date, mock_context
    ):
        mock_variable_get.return_value = None
        s3_client = mock.MagicMock()
        mock_boto3.client.return_value = s3_client
        DatasetService.update_datasets(mock_context)
        mock_context["outlet_events"]["dag:task:alias"].add.assert_has_calls(
            [
                mock.call(Dataset("dag:task")),
                mock.call(Dataset("datalake_ebdb_contract.contract")),
                mock.call(Dataset("dag:task:first-run-of-day")),
                mock.call(Dataset("datalake_ebdb_contract.contract:first-run-of-day")),
            ],
            any_order=True,
        )
        s3_client.put_object.assert_not_called()

    @mock.patch("bietlejuice.services.dataset_service.boto3")
    @mock.patch("bietlejuice.services.dataset_service.Variable.get")
    def test_update_datasets_should_write_list_of_dicts_to_s3_when_bucket_set(
        self, mock_variable_get, mock_boto3, mock_is_first_run_of_date, mock_context
    ):
        def variable_get(key, default=None):
            return (
                "my-dataset-events-bucket"
                if key == "DATASET_EVENTS_S3_BUCKET"
                else default
            )

        mock_variable_get.side_effect = variable_get
        s3_client = mock.MagicMock()
        mock_session = mock.MagicMock()
        mock_session.client.side_effect = lambda service: (
            mock.MagicMock(get_caller_identity=mock.MagicMock(return_value={}))
            if service == "sts"
            else s3_client
        )
        mock_boto3.Session.return_value = mock_session
        mock_context["ti"].dag_id = "dag"
        mock_context["ti"].run_id = "dag_run_id"

        DatasetService.update_datasets(mock_context)

        s3_client.put_object.assert_called_once()
        call_kw = s3_client.put_object.call_args[1]
        assert call_kw["Bucket"] == "my-dataset-events-bucket"
        assert call_kw["Key"].startswith("airflow_datasets/dataset_events/year=")
        body = json.loads(call_kw["Body"])
        assert isinstance(body, list)
        assert len(body) == 4
        event_types = {e["event_type"] for e in body}
        assert "normal" in event_types
        assert "first_run_of_day" in event_types
        dataset_names = {e["dataset_name"] for e in body}
        assert "dag:task" in dataset_names
        assert "datalake_ebdb_contract.contract" in dataset_names
        assert "dag:task:first-run-of-day" in dataset_names
        assert "datalake_ebdb_contract.contract:first-run-of-day" in dataset_names
        assert body[0]["dag_id"] == "dag"
        assert body[0]["task_id"] == "task"
        assert body[0]["dataset_alias"] == "dag:task:alias"

    @mock.patch("bietlejuice.services.dataset_service.boto3")
    @mock.patch("bietlejuice.services.dataset_service.Variable.get")
    def test_update_datasets_should_write_reprocessing_list_to_s3_when_bucket_set(
        self, mock_variable_get, mock_boto3, mock_is_first_run_of_date, mock_context
    ):
        def variable_get(key, default=None):
            return (
                "my-dataset-events-bucket"
                if key == "DATASET_EVENTS_S3_BUCKET"
                else default
            )

        mock_variable_get.side_effect = variable_get
        s3_client = mock.MagicMock()
        mock_session = mock.MagicMock()
        mock_session.client.side_effect = lambda service: (
            mock.MagicMock(get_caller_identity=mock.MagicMock(return_value={}))
            if service == "sts"
            else s3_client
        )
        mock_boto3.Session.return_value = mock_session
        mock_context["params"]["run_type"] = "reprocessing_run"
        mock_context["ti"].dag_id = "dag"
        mock_context["ti"].run_id = "dag_run_id"

        DatasetService.update_datasets(mock_context)

        s3_client.put_object.assert_called_once()
        call_kw = s3_client.put_object.call_args[1]
        body = json.loads(call_kw["Body"])
        assert isinstance(body, list)
        assert len(body) == 2
        assert all(e["event_type"] == "reprocessing" for e in body)
        dataset_names = {e["dataset_name"] for e in body}
        assert "dag:task:reprocessing" in dataset_names
        assert "datalake_ebdb_contract.contract:reprocessing" in dataset_names
        assert body[0]["extra"]["reprocessing_source"] == "dag"
        assert body[0]["extra"]["reprocessing_date"] == FAKE_TIME.date().isoformat()

    def test_update_datasets_should_not_emit_table_event_when_table_name_missing(
        self, mock_is_first_run_of_date, mock_context
    ):
        mock_is_first_run_of_date.return_value = True
        del mock_context["params"]["table_name"]
        del mock_context["params"]["schema"]
        del mock_context["params"]["layer"]

        DatasetService.update_datasets(mock_context)

        mock_context["outlet_events"]["dag:task:alias"].add.assert_has_calls(
            [
                mock.call(Dataset("dag:task")),
                mock.call(Dataset("dag:task:first-run-of-day")),
            ],
            any_order=True,
        )
        table_calls = [
            c
            for c in mock_context["outlet_events"]["dag:task:alias"].add.call_args_list
            if "datalake_" in str(c) or "dw_" in str(c) or "metric_" in str(c)
        ]
        assert len(table_calls) == 0

    def test_build_table_dataset_name_returns_none_when_params_missing(self):
        context = {"params": {"run_type": "impact_downstream_dependents"}}
        assert DatasetService._build_table_dataset_name(context) is None

    def test_build_table_dataset_name_returns_qualified_name(self):
        context = {
            "params": {
                "schema": "ebdb_contract",
                "table_name": "contract",
                "layer": "enrich",
            }
        }
        assert (
            DatasetService._build_table_dataset_name(context)
            == "datalake_ebdb_contract.contract"
        )

    def test_build_table_dataset_name_for_dw_layer(self):
        context = {
            "params": {
                "schema": "rent",
                "table_name": "fact_contracts",
                "layer": "dw",
            }
        }
        assert (
            DatasetService._build_table_dataset_name(context)
            == "dw_rent.fact_contracts"
        )

    def test_build_table_dataset_name_for_clean_layer(self):
        context = {
            "params": {
                "schema": "condominium_payments",
                "table_name": "non_payment_report",
                "layer": "clean",
            }
        }
        assert (
            DatasetService._build_table_dataset_name(context)
            == "datalake_condominium_payments_clean.non_payment_report"
        )

    def test_build_table_dataset_name_for_core_layer(self):
        context = {
            "params": {
                "schema": "core_house",
                "table_name": "house",
                "layer": "core",
            }
        }
        assert DatasetService._build_table_dataset_name(context) == "core_house.house"

    def test_build_table_dataset_name_returns_none_for_unknown_layer(self):
        context = {
            "params": {
                "schema": "some_schema",
                "table_name": "some_table",
                "layer": "unknown_layer",
            }
        }
        assert DatasetService._build_table_dataset_name(context) is None

    def test_build_table_dataset_name_lowercases_mixed_case_table(self):
        context = {
            "params": {
                "schema": "ebdb",
                "table_name": "Contrato_AUD",
                "layer": "raw",
            }
        }
        assert (
            DatasetService._build_table_dataset_name(context)
            == "datalake_ebdb_raw.contrato_aud"
        )

    def test_build_table_dataset_name_for_transformation_with_grade(self):
        context = {
            "params": {
                "schema": "terminator_test",
                "table_name": "termination",
                "layer": "transformation",
                "transformation_grade": "clean",
            }
        }
        assert (
            DatasetService._build_table_dataset_name(context)
            == "transformation_terminator_test_clean.termination"
        )

    def test_build_table_dataset_name_for_transformation_without_grade(self):
        context = {
            "params": {
                "schema": "terminator_test",
                "table_name": "termination",
                "layer": "transformation",
            }
        }
        assert DatasetService._build_table_dataset_name(context) is None

    def test_build_table_dataset_name_for_consumption_ignores_missing_grade(self):
        context = {
            "params": {
                "schema": "offboarding_test",
                "table_name": "dim_termination",
                "layer": "consumption",
            }
        }
        assert (
            DatasetService._build_table_dataset_name(context)
            == "offboarding_test.dim_termination"
        )

    @mock.patch("bietlejuice.services.dataset_service.Variable.get")
    @mock.patch.object(DatasetService, "_get_boto3_session_for_dataset_events")
    def test_archive_dataset_events_to_s3_success(self, mock_get_session, mock_var_get):
        mock_var_get.return_value = "test-bucket"
        mock_session = mock.MagicMock()
        mock_s3_client = mock.MagicMock()
        mock_session.client.return_value = mock_s3_client
        mock_get_session.return_value = mock_session

        events = [
            {"id": 1, "uri": "test://table1", "source_dag_id": "dag1"},
            {"id": 2, "uri": "test://table2", "source_dag_id": "dag2"},
        ]

        key = DatasetService.archive_dataset_events_to_s3(events)

        assert key.startswith("airflow_datasets/dataset_events_reset_archive/year=")
        assert key.endswith(".json")
        mock_s3_client.put_object.assert_called_once()
        call_kwargs = mock_s3_client.put_object.call_args.kwargs
        assert call_kwargs["Bucket"] == "test-bucket"
        assert call_kwargs["Key"] == key
        assert call_kwargs["ContentType"] == "application/json"
        body_events = json.loads(call_kwargs["Body"])
        assert len(body_events) == 2
        assert body_events[0]["uri"] == "test://table1"

    @mock.patch("bietlejuice.services.dataset_service.Variable.get")
    @mock.patch.object(DatasetService, "_get_boto3_session_for_dataset_events")
    def test_archive_dataset_events_to_s3_raises_when_bucket_unset(
        self, mock_get_session, mock_var_get
    ):
        mock_var_get.return_value = None
        mock_session = mock.MagicMock()
        mock_get_session.return_value = mock_session

        events = [{"id": 1, "uri": "test://table1"}]

        with pytest.raises(
            AirflowException, match="Variable DATASET_EVENTS_S3_BUCKET is not set"
        ):
            DatasetService.archive_dataset_events_to_s3(events)

        mock_session.client.assert_not_called()

    @mock.patch("bietlejuice.services.dataset_service.Variable.get")
    @mock.patch.object(DatasetService, "_get_boto3_session_for_dataset_events")
    def test_archive_dataset_events_to_s3_propagates_s3_exception(
        self, mock_get_session, mock_var_get
    ):
        mock_var_get.return_value = "test-bucket"
        mock_session = mock.MagicMock()
        mock_s3_client = mock.MagicMock()
        mock_s3_client.put_object.side_effect = RuntimeError("S3 PutObject failure")
        mock_session.client.return_value = mock_s3_client
        mock_get_session.return_value = mock_session

        events = [{"id": 1, "uri": "test://table1"}]

        with pytest.raises(RuntimeError, match="S3 PutObject failure"):
            DatasetService.archive_dataset_events_to_s3(events)


def dataset_equals(d1: BaseDataset, d2: BaseDataset) -> bool:
    """
    Compare two datasets to see if they are equal.
    """
    if isinstance(d1, Dataset) and isinstance(d2, Dataset):
        return d1.uri == d2.uri
    if (isinstance(d1, DatasetAny) and isinstance(d2, DatasetAny)) or (
        isinstance(d1, DatasetAll) and isinstance(d2, DatasetAll)
    ):
        if len(d1.objects) != len(d2.objects):
            return False
        for obj in d1.objects:
            if not any(dataset_equals(obj, d2_obj) for d2_obj in d2.objects):
                return False
        return True
    return False
