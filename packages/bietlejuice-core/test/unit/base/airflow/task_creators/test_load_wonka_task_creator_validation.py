from unittest import mock

from bietlejuice.base.airflow.task_creators.load_wonka_task_creator import (
    LoadWonkaTaskCreator,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.layer_enum import LayerEnum

_VALIDATION_DB = "cluster_validation"
_VALIDATION_TABLE = "wonka___my_table"
_SENTINEL_BUCKET = "sentinel-bucket"
_CONFIGURATION_SERVICE_PATH = (
    "bietlejuice.base.airflow.task_creators.load_wonka_task_creator"
    ".ConfigurationService"
)


def _make_table_attributes(table_name="my_table"):
    return TableAttributes(
        dag_args={"name": "some-pipeline"},
        workflow_args={},
        layer=LayerEnum.RAW,
        table_name=table_name,
    )


def _make_context(is_validation):
    ctx = mock.MagicMock()
    ctx.is_validation = is_validation
    ctx.environment = "prod"
    ctx.bucket = "s3://bucket"
    ctx.workflow_args = {}
    ctx.dag_args = {"name": "some-pipeline"}
    return ctx


class TestLoadWonkaTaskCreatorValidation:
    def _creator(self, is_validation):
        return LoadWonkaTaskCreator(
            dag_execution_context=_make_context(is_validation),
            produce_datasets=False,
        )

    def test_validation_appends_target_and_datalake_bucket_args(self):
        creator = self._creator(is_validation=True)
        table_attrs = _make_table_attributes()
        with (
            mock.patch(_CONFIGURATION_SERVICE_PATH) as mock_config_service,
            mock.patch.object(
                table_attrs,
                "get_validation_write_target",
                return_value=(_VALIDATION_DB, _VALIDATION_TABLE),
            ),
        ):
            mock_config_service.return_value.get_config.return_value = _SENTINEL_BUCKET
            params = creator._get_parameters(table_attrs)

        assert params == [
            "some_pipeline",
            "--target-database-name",
            _VALIDATION_DB,
            "--target-table-name",
            _VALIDATION_TABLE,
            "--datalake-bucket",
            _SENTINEL_BUCKET,
        ]
        mock_config_service.return_value.get_config.assert_called_once_with(
            "datalake_bucket"
        )

    def test_no_validation_returns_pipeline_package_only(self):
        creator = self._creator(is_validation=False)
        table_attrs = _make_table_attributes()
        params = creator._get_parameters(table_attrs)

        assert params == ["some_pipeline"]

    def test_missing_is_validation_returns_pipeline_package_only(self):
        ctx = _make_context(is_validation=False)
        del ctx.is_validation
        creator = LoadWonkaTaskCreator(
            dag_execution_context=ctx, produce_datasets=False
        )
        table_attrs = _make_table_attributes()
        params = creator._get_parameters(table_attrs)

        assert params == ["some_pipeline"]
