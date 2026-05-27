from unittest import mock

from bietlejuice.base.airflow.task_creators.load_api_raw_task_creator import (
    LoadAPIRawTaskCreator,
)
from bietlejuice.base.airflow.task_creators.load_cdc_clean_task_creator import (
    LoadCDCCleanTaskCreator,
)
from bietlejuice.base.airflow.task_creators.load_cdc_raw_task_creator import (
    LoadCDCRawTaskCreator,
)
from bietlejuice.base.airflow.task_creators.load_cdc_transactional_task_creator import (
    LoadCDCTransactionalTaskCreator,
)
from bietlejuice.base.airflow.task_creators.load_postgres_raw_task_creator import (
    LoadPostgresRawTaskCreator,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.layer_enum import LayerEnum

_VALIDATION_DB = "cluster_validation"
_VALIDATION_TABLE = "datalake_test_clean___my_table"


def _make_table_attributes(table_name="my_table"):
    return TableAttributes(
        dag_args={"name": "test_dag"},
        workflow_args={},
        layer=LayerEnum.RAW,
        table_name=table_name,
    )


def _make_cdc_context(is_validation):
    ctx = mock.MagicMock()
    ctx.is_validation = is_validation
    ctx.environment = "prod"
    ctx.bucket = "s3://bucket"
    ctx.incoming_bucket = "s3://incoming"
    ctx.load_start_date = "2024-01-01"
    ctx.load_end_date = "2024-01-02"
    ctx.workflow_args = {"database_type": "postgres"}
    ctx.dag_args = {"name": "test_dag"}
    return ctx


def _make_context(is_validation):
    ctx = mock.MagicMock()
    ctx.is_validation = is_validation
    ctx.environment = "prod"
    ctx.bucket = "s3://bucket"
    ctx.incoming_bucket = "s3://incoming"
    ctx.execution_date = "2024-01-01"
    ctx.load_start_date = "2024-01-01"
    ctx.load_end_date = "2024-01-02"
    ctx.workflow_args = {}
    ctx.dag_args = {"name": "test_dag"}
    return ctx


class TestLoadCDCRawTaskCreatorValidation:
    def _creator(self, is_validation):
        return LoadCDCRawTaskCreator(
            dag_execution_context=_make_cdc_context(is_validation),
            produce_datasets=False,
        )

    def test_validation_appends_target_args(self):
        creator = self._creator(is_validation=True)
        table_attrs = _make_table_attributes()
        with mock.patch.object(
            table_attrs,
            "get_validation_write_target",
            return_value=(_VALIDATION_DB, _VALIDATION_TABLE),
        ):
            params = creator._get_parameters(table_attrs)

        assert "--target-database-name" in params
        assert _VALIDATION_DB in params
        assert "--target-table-name" in params
        assert _VALIDATION_TABLE in params

    def test_no_validation_does_not_append_target_args(self):
        creator = self._creator(is_validation=False)
        table_attrs = _make_table_attributes()
        params = creator._get_parameters(table_attrs)

        assert "--target-database-name" not in params
        assert "--target-table-name" not in params

    def test_missing_is_validation_does_not_append_target_args(self):
        ctx = _make_cdc_context(is_validation=False)
        del ctx.is_validation
        creator = LoadCDCRawTaskCreator(
            dag_execution_context=ctx, produce_datasets=False
        )
        table_attrs = _make_table_attributes()
        params = creator._get_parameters(table_attrs)

        assert "--target-database-name" not in params
        assert "--target-table-name" not in params


class TestLoadCDCCleanTaskCreatorValidation:
    def _creator(self, is_validation):
        ctx = mock.MagicMock()
        ctx.is_validation = is_validation
        ctx.environment = "prod"
        ctx.bucket = "s3://bucket"
        ctx.load_start_date = "2024-01-01"
        ctx.load_end_date = "2024-01-02"
        ctx.dag_args = {"name": "test_dag"}
        ctx.workflow_args = {}

        config_service = mock.MagicMock()
        config_service.get_config.return_value = "mock-doc-bucket"

        return LoadCDCCleanTaskCreator(
            dag_execution_context=ctx,
            config_service=config_service,
            produce_datasets=False,
        )

    def test_validation_appends_target_args(self):
        creator = self._creator(is_validation=True)
        table_attrs = _make_table_attributes()
        with mock.patch.object(
            table_attrs,
            "get_validation_write_target",
            return_value=(_VALIDATION_DB, _VALIDATION_TABLE),
        ):
            params = creator._get_parameters(table_attrs)

        assert "--target-database-name" in params
        assert _VALIDATION_DB in params
        assert "--target-table-name" in params
        assert _VALIDATION_TABLE in params

    def test_no_validation_does_not_append_target_args(self):
        creator = self._creator(is_validation=False)
        table_attrs = _make_table_attributes()
        params = creator._get_parameters(table_attrs)

        assert "--target-database-name" not in params
        assert "--target-table-name" not in params

    def test_missing_is_validation_does_not_append_target_args(self):
        ctx = mock.MagicMock()
        del ctx.is_validation
        ctx.environment = "prod"
        ctx.bucket = "s3://bucket"
        ctx.load_start_date = "2024-01-01"
        ctx.load_end_date = "2024-01-02"
        ctx.dag_args = {"name": "test_dag"}
        ctx.workflow_args = {}

        config_service = mock.MagicMock()
        config_service.get_config.return_value = "mock-doc-bucket"

        creator = LoadCDCCleanTaskCreator(
            dag_execution_context=ctx,
            config_service=config_service,
            produce_datasets=False,
        )
        table_attrs = _make_table_attributes()
        params = creator._get_parameters(table_attrs)

        assert "--target-database-name" not in params
        assert "--target-table-name" not in params


class TestLoadCDCTransactionalTaskCreatorValidation:
    def _creator(self, is_validation):
        return LoadCDCTransactionalTaskCreator(
            dag_execution_context=_make_cdc_context(is_validation),
            produce_datasets=False,
        )

    def test_validation_appends_target_args(self):
        creator = self._creator(is_validation=True)
        table_attrs = _make_table_attributes()
        with mock.patch.object(
            table_attrs,
            "get_validation_write_target",
            return_value=(_VALIDATION_DB, _VALIDATION_TABLE),
        ):
            params = creator._get_parameters(table_attrs)

        assert "--target-database-name" in params
        assert _VALIDATION_DB in params
        assert "--target-table-name" in params
        assert _VALIDATION_TABLE in params

    def test_no_validation_does_not_append_target_args(self):
        creator = self._creator(is_validation=False)
        table_attrs = _make_table_attributes()
        params = creator._get_parameters(table_attrs)

        assert "--target-database-name" not in params
        assert "--target-table-name" not in params

    def test_missing_is_validation_does_not_append_target_args(self):
        ctx = _make_cdc_context(is_validation=False)
        del ctx.is_validation
        creator = LoadCDCTransactionalTaskCreator(
            dag_execution_context=ctx, produce_datasets=False
        )
        table_attrs = _make_table_attributes()
        params = creator._get_parameters(table_attrs)

        assert "--target-database-name" not in params
        assert "--target-table-name" not in params


class TestLoadPostgresRawTaskCreatorValidation:
    def _creator(self, is_validation):
        return LoadPostgresRawTaskCreator(
            dag_execution_context=_make_context(is_validation),
            produce_datasets=False,
        )

    def test_validation_appends_target_args(self):
        creator = self._creator(is_validation=True)
        table_attrs = _make_table_attributes()
        with mock.patch.object(
            table_attrs,
            "get_validation_write_target",
            return_value=(_VALIDATION_DB, _VALIDATION_TABLE),
        ):
            params = creator._get_parameters(table_attrs)

        assert "--target-database-name" in params
        assert _VALIDATION_DB in params
        assert "--target-table-name" in params
        assert _VALIDATION_TABLE in params

    def test_no_validation_does_not_append_target_args(self):
        creator = self._creator(is_validation=False)
        table_attrs = _make_table_attributes()
        params = creator._get_parameters(table_attrs)

        assert "--target-database-name" not in params
        assert "--target-table-name" not in params

    def test_missing_is_validation_does_not_append_target_args(self):
        ctx = _make_context(is_validation=False)
        del ctx.is_validation
        creator = LoadPostgresRawTaskCreator(
            dag_execution_context=ctx, produce_datasets=False
        )
        table_attrs = _make_table_attributes()
        params = creator._get_parameters(table_attrs)

        assert "--target-database-name" not in params
        assert "--target-table-name" not in params


class TestLoadAPIRawTaskCreatorValidation:
    def _creator(self, is_validation):
        return LoadAPIRawTaskCreator(
            dag_execution_context=_make_context(is_validation),
            produce_datasets=False,
        )

    def test_validation_appends_target_args(self):
        creator = self._creator(is_validation=True)
        table_attrs = _make_table_attributes()
        with mock.patch.object(
            table_attrs,
            "get_validation_write_target",
            return_value=(_VALIDATION_DB, _VALIDATION_TABLE),
        ):
            params = creator._get_parameters(table_attrs)

        assert "--target-database-name" in params
        assert _VALIDATION_DB in params
        assert "--target-table-name" in params
        assert _VALIDATION_TABLE in params

    def test_no_validation_does_not_append_target_args(self):
        creator = self._creator(is_validation=False)
        table_attrs = _make_table_attributes()
        params = creator._get_parameters(table_attrs)

        assert "--target-database-name" not in params
        assert "--target-table-name" not in params

    def test_missing_is_validation_does_not_append_target_args(self):
        ctx = _make_context(is_validation=False)
        del ctx.is_validation
        creator = LoadAPIRawTaskCreator(
            dag_execution_context=ctx, produce_datasets=False
        )
        table_attrs = _make_table_attributes()
        params = creator._get_parameters(table_attrs)

        assert "--target-database-name" not in params
        assert "--target-table-name" not in params
