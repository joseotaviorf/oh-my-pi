import pytest
import pendulum
import datetime
from bietlejuice.services.dataset_service import DatasetService
from airflow.datasets import Dataset, DatasetAll, DatasetAny, BaseDataset
from unittest import mock

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
        self
    ):
        dependencies = []

        result = DatasetService.get_dag_datasets_from_dependencies(dependencies)

        assert result is None

    def test_get_dag_datasets_from_dependencies_should_structure_dataset_object_correctly(
        self
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
        self
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
        self
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
        self
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
            "params": {"run_type": "impact_downstream_dependents"},
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
        return (
            mock_create_session.return_value.query.return_value.filter.return_value.first
        )

    def test_update_datasets_should_do_nothing_if_is_test_run(self, mock_context):
        mock_context["params"]["run_type"] = "test_run"

        DatasetService.update_datasets(mock_context)

        mock_context["outlet_events"]["dag:task:alias"].add.assert_not_called()

    def test_update_datasets_should_add_normal_dataset_by_default(self, mock_context):
        DatasetService.update_datasets(mock_context)

        mock_context["outlet_events"]["dag:task:alias"].add.assert_has_calls(
            [
                mock.call(Dataset("validation-dag:task")),
                mock.call(Dataset("validation-dag:task:first-run-of-day")),
            ],
            any_order=True,
        )

    def test_update_datasets_should_add_reprocessing_dataset_if_is_reprocessing_run(
        self, mock_context
    ):
        mock_context["params"]["run_type"] = "reprocessing_run"
        DatasetService.update_datasets(mock_context)

        mock_context["outlet_events"]["dag:task:alias"].add.assert_called_once_with(
            Dataset("validation-dag:task:reprocessing"),
            extra={
                "reprocessing_source": "dag",
                "reprocessing_date": FAKE_TIME.date().isoformat(),
            },
        )

    def test_update_datasets_should_add_reprocessing_dataset_if_triggering_dataset_is_reprocessing(
        self, mock_context
    ):
        dataset_event = mock.MagicMock()
        dataset_event.extra = {
            "reprocessing_source": "dag2",
            "reprocessing_date": FAKE_TIME.date().isoformat(),
        }
        mock_context["triggering_dataset_events"] = {
            "dag2:task:reprocessing": [dataset_event]
        }
        DatasetService.update_datasets(mock_context)

        mock_context["outlet_events"]["dag:task:alias"].add.assert_called_once_with(
            Dataset("validation-dag:task:reprocessing"),
            extra={
                "reprocessing_source": "dag2",
                "reprocessing_date": FAKE_TIME.date().isoformat(),
            },
        )

    def test_update_datasets_should_add_normal_dataset_if_triggering_dataset_is_not_reprocessing(
        self, mock_context
    ):
        mock_context["triggering_dataset_events"] = {"dag2:task": mock.MagicMock()}
        DatasetService.update_datasets(mock_context)

        mock_context["outlet_events"]["dag:task:alias"].add.assert_has_calls(
            [
                mock.call(Dataset("validation-dag:task")),
                mock.call(Dataset("validation-dag:task:first-run-of-day")),
            ],
            any_order=True,
        )

    def test_update_datasets_should_update_xcom(self, mock_context):
        DatasetService.update_datasets(mock_context)

        mock_context["ti"].xcom_push.assert_called_once_with(
            key="last_run_start_date", value=mock_context["ti"].start_date
        )

    def test_if_last_start_date_is_in_the_past_add_first_run_of_day_dataset(
        self, mock_context
    ):
        mock_context["ti"].xcom_pull.return_value = pendulum.datetime(2024, 12, 31)

        DatasetService.update_datasets(mock_context)

        mock_context["outlet_events"]["dag:task:alias"].add.assert_has_calls(
            [
                mock.call(Dataset("validation-dag:task")),
                mock.call(Dataset("validation-dag:task:first-run-of-day")),
            ],
            any_order=True,
        )

    def test_if_last_execution_date_is_equal_to_date_do_not_add_first_run_of_day_dataset(
        self, mock_context
    ):
        mock_context["ti"].xcom_pull.return_value = pendulum.datetime(2025, 1, 2)

        DatasetService.update_datasets(mock_context)

        mock_context["outlet_events"]["dag:task:alias"].add.assert_called_once_with(
            Dataset("validation-dag:task")
        )

    def test_if_it_is_a_rerun_it_should_not_update_datasets(
        self, mock_context, database_query_function
    ):
        database_query_function.return_value = "dataset-event"

        DatasetService.update_datasets(mock_context)

        mock_context["outlet_events"]["dag:task:alias"].add.assert_not_called()

    def test_should_not_trigger_reprocessing_if_event_from_a_previous_date(
        self, mock_context
    ):
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
