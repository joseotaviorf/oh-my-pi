"""Unit tests for the salesforce_marketing_cloud Airflow DAG module."""

from unittest.mock import MagicMock

import pytest


def parameters_as_dict(job_parameters):
    """Turn the flat ["--flag", "value", ...] job parameters back into a dict."""
    flags = job_parameters[::2]
    values = job_parameters[1::2]
    return {flag.lstrip("-"): value for flag, value in zip(flags, values)}


def _calls_for_entry_point(spark_task_calls, entry_point):
    return [
        call
        for call in spark_task_calls
        if call.kwargs["spark_job_path"].endswith(entry_point)
    ]


@pytest.fixture(scope="module")
def raw_calls(spark_task_calls):
    return _calls_for_entry_point(spark_task_calls, "raw.py")


@pytest.fixture(scope="module")
def clean_calls(spark_task_calls):
    return _calls_for_entry_point(spark_task_calls, "clean.py")


class TestRawTasks:
    def test_one_task_per_object(self, raw_calls, config):
        # Arrange / Act
        task_ids = [call.kwargs["task_id"] for call in raw_calls]

        # Assert
        raw_schema = config["raw_schema"]
        assert task_ids == [
            f"load_{raw_schema}_sonia_closing",
            f"load_{raw_schema}_sonia_ep2ds_v2",
        ]

    def test_forwards_the_external_key(self, raw_calls, config):
        # Arrange / Act
        by_table = {}
        for call in raw_calls:
            parameters = parameters_as_dict(call.kwargs["job_parameters"])
            by_table[parameters["target_table"]] = parameters["external_key"]

        # Assert
        expected = {
            table: object_conf["external_identifier"]
            for table, object_conf in config["objects_config"].items()
        }
        assert by_table == expected

    def test_writes_to_the_raw_schema(self, raw_calls, config):
        for call in raw_calls:
            parameters = parameters_as_dict(call.kwargs["job_parameters"])

            assert parameters["target_schema"] == config["raw_schema"]

    def test_runs_the_uploaded_entry_point(self, raw_calls, config):
        repo_path = config["databricks_bietlejuice_repo_path"]

        assert raw_calls[0].kwargs["spark_job_path"] == (
            f"{repo_path}/spark_jobs/salesforce_marketing_cloud/raw.py"
        )


class TestCleanTasks:
    def test_one_task_per_object(self, clean_calls, config):
        # Arrange / Act
        task_ids = [call.kwargs["task_id"] for call in clean_calls]

        # Assert
        clean_schema = config["clean_schema"]
        assert task_ids == [
            f"load_{clean_schema}_sonia_closing",
            f"load_{clean_schema}_sonia_ep2ds_v2",
        ]

    def test_carries_the_source_and_target_schemas(self, clean_calls, config):
        for call in clean_calls:
            parameters = parameters_as_dict(call.kwargs["job_parameters"])

            assert parameters["source_schema"] == config["raw_schema"]
            assert parameters["target_schema"] == config["clean_schema"]

    def test_registers_the_table_in_trino(self, clean_calls):
        for call in clean_calls:
            parameters = parameters_as_dict(call.kwargs["job_parameters"])

            assert parameters["sync_hive"] == "True"

    def test_emits_a_dataset_event_per_table(self, dag_module, clean_calls):
        attach = dag_module.DatasetAdder.attach_dataset_to_task

        assert attach.call_count == len(clean_calls)

    def test_runs_the_uploaded_entry_point(self, clean_calls, config):
        repo_path = config["databricks_bietlejuice_repo_path"]

        assert clean_calls[0].kwargs["spark_job_path"] == (
            f"{repo_path}/spark_jobs/salesforce_marketing_cloud/clean.py"
        )


class TestSharedParameters:
    def test_every_task_gets_the_bucket_dag_name_and_partition_date(
        self, spark_task_calls, config
    ):
        for call in spark_task_calls:
            parameters = parameters_as_dict(call.kwargs["job_parameters"])

            assert parameters["bucket"] == config["datalake_bucket"]
            assert parameters["dag_name"] == "salesforce_marketing_cloud"
            assert parameters["partition_date"] == "{{ data_interval_start | ds }}"

    def test_job_name_matches_the_task_id(self, spark_task_calls):
        for call in spark_task_calls:
            parameters = parameters_as_dict(call.kwargs["job_parameters"])

            assert parameters["job_name"] == call.kwargs["task_id"]


class TestCreateSstTask:
    @pytest.fixture
    def context(self):
        def _return_kwargs(**kwargs):
            return kwargs

        ctx = MagicMock()
        ctx.job_cluster_engine.create_spark_python_task.side_effect = _return_kwargs
        return ctx

    def test_defaults_the_task_id_from_schema_and_table(self, dag_module, context):
        # Arrange / Act
        call = dag_module.create_sst_task(
            dag_execution_context=context,
            target_schema="schema",
            target_table="table",
            entry_point="raw",
            parameters={},
        )

        # Assert
        assert call["task_id"] == "load_schema_table"

    @pytest.mark.parametrize("entry_point", ["raw", "raw.py"])
    def test_appends_the_py_suffix_only_when_missing(
        self, dag_module, context, entry_point
    ):
        # Arrange / Act
        call = dag_module.create_sst_task(
            dag_execution_context=context,
            target_schema="schema",
            target_table="table",
            entry_point=entry_point,
            parameters={},
        )

        # Assert
        assert call["spark_job_path"].endswith("raw.py")


class TestDagConfiguration:
    def test_builds_the_namespaced_dag_id(self, dag_module):
        assert dag_module.dag.dag_id == "bietlejuice.salesforce_marketing_cloud"

    def test_uses_the_emr_cluster_preset(self, dag_module, config):
        assert dag_module.CLUSTER_ARGS == config["cluster"]
