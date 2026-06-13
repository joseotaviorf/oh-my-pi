"""Unit tests for SupportJourneyServicesCoreModelPipeline (services table)."""

import json
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

import pytest
import yaml

from bietlejuice.base.core_models.helpers.schema_validator import SchemaValidationError
from bietlejuice.base.sst.domains.salesforce.core_models.config_loader import (
    table_spec_from_cfg,
)
from bietlejuice.base.sst.pipelines.core_model.support_journey import (
    services as services_module,
)


def _find_project_root() -> Path:
    current = Path(__file__).resolve().parent
    while current != current.parent:
        if (current / ".git").exists():
            return current
        current = current.parent
    raise RuntimeError("Could not locate project root from test path")


@pytest.fixture
def table_spec():
    spec_path = (
        _find_project_root() / "dags/core/core_support_journey/tables/services.yml"
    )
    return yaml.safe_load(spec_path.read_text(encoding="utf-8"))


@pytest.fixture
def cfg(table_spec):
    return SimpleNamespace(
        job_name="load_core_support_journey_services",
        dag_name="core_support_journey",
        partition_date="2026-05-27",
        partition_hour="14",
        bucket="test-bucket",
        table_config_json=json.dumps(table_spec),
    )


@pytest.fixture
def pipeline_with_spec(cfg, table_spec):
    pipeline = services_module.SupportJourneyServicesCoreModelPipeline(cfg)
    pipeline.table_spec = table_spec_from_cfg(cfg)
    return pipeline


class TestSupportJourneyServicesCoreModelPipelineInit:
    def test_table_spec_loaded_from_json_string(self, cfg, table_spec):
        spec = table_spec_from_cfg(cfg)

        assert spec["target_table"] == table_spec["target_table"]
        assert spec["merge_on"] == table_spec["merge_on"]

    def test_table_spec_accepts_dict_config(self, table_spec):
        cfg = SimpleNamespace(
            job_name="load_core_support_journey_services",
            dag_name="core_support_journey",
            partition_date="2026-05-27",
            partition_hour="14",
            bucket="test-bucket",
            table_config_json=table_spec,
        )

        assert table_spec_from_cfg(cfg) == table_spec

    @mock.patch(
        "bietlejuice.base.sst.domains.salesforce.core_models.config_loader.load_table_spec_from_relative_path"
    )
    def test_table_spec_loaded_from_relative_path(self, mock_load, table_spec):
        mock_load.return_value = table_spec
        cfg = SimpleNamespace(
            table_config_relative_path="core/core_support_journey/tables/services.yml"
        )

        assert table_spec_from_cfg(cfg) == table_spec
        mock_load.assert_called_once_with(
            "core/core_support_journey/tables/services.yml"
        )


class TestSupportJourneyServicesCoreModelPipelineCreateCoreModel:
    @mock.patch.object(services_module, "partition_has_data")
    def test_skips_when_partition_already_exists(
        self, mock_partition_has_data, cfg, pipeline_with_spec
    ):
        # arrange
        spark = mock.MagicMock()
        mock_partition_has_data.return_value = True
        pipeline = pipeline_with_spec

        # act
        pipeline.create_core_model(spark)

        # assert
        mock_partition_has_data.assert_called_once_with(
            spark,
            "core_support_journey.services",
            cfg.partition_date,
            None,
        )
        spark.table.assert_not_called()

    @mock.patch.object(services_module, "partition_has_data")
    def test_returns_when_event_sources_are_empty(
        self, mock_partition_has_data, cfg, pipeline_with_spec
    ):
        # arrange
        spark = mock.MagicMock()
        empty_df = mock.MagicMock()
        empty_df.isEmpty.return_value = True
        table_df = mock.MagicMock()
        table_df.where.return_value = empty_df
        spark.table.return_value = table_df
        mock_partition_has_data.return_value = False
        pipeline = pipeline_with_spec

        # act
        pipeline.create_core_model(spark)

        # assert
        assert spark.table.call_count == 2
        empty_df.isEmpty.assert_called()

    @mock.patch.object(services_module, "DataFrameDeltaTableLoaderPipeline")
    @mock.patch.object(services_module, "SchemaValidator")
    @mock.patch.object(services_module, "get_versioning_df")
    @mock.patch.object(services_module, "_complete_dataframe_schema")
    @mock.patch.object(services_module, "_table_exists")
    @mock.patch.object(
        services_module.SupportJourneyServicesCoreModelPipeline, "_build_target_df"
    )
    @mock.patch.object(services_module, "partition_has_data")
    def test_runs_delta_pipeline_when_schema_is_valid(
        self,
        mock_partition_has_data,
        mock_build_target_df,
        mock_table_exists,
        mock_complete_schema,
        mock_get_versioning_df,
        mock_schema_validator_cls,
        mock_pipeline_cls,
        cfg,
        pipeline_with_spec,
    ):
        # arrange
        mock_partition_has_data.return_value = False
        mock_table_exists.return_value = False

        non_empty_df = mock.MagicMock()
        non_empty_df.isEmpty.return_value = False
        table_df = mock.MagicMock()
        table_df.where.return_value = non_empty_df
        spark = mock.MagicMock()
        spark.table.return_value = table_df

        target_df = mock.MagicMock()
        mock_build_target_df.return_value = target_df

        versioned_df = mock.MagicMock()
        versioned_df.select.return_value = versioned_df
        mock_get_versioning_df.return_value = versioned_df
        mock_complete_schema.return_value = target_df

        validator = mock_schema_validator_cls.return_value
        validator.validate_schema.return_value = True

        mock_pipeline = mock_pipeline_cls.return_value
        pipeline = pipeline_with_spec

        # act
        pipeline.create_core_model(spark)

        # assert
        mock_build_target_df.assert_called_once()
        mock_pipeline_cls.assert_called_once()
        mock_pipeline.run.assert_called_once()

    @mock.patch.object(services_module, "SchemaValidator")
    @mock.patch.object(services_module, "get_versioning_df")
    @mock.patch.object(services_module, "_complete_dataframe_schema")
    @mock.patch.object(services_module, "_table_exists")
    @mock.patch.object(
        services_module.SupportJourneyServicesCoreModelPipeline, "_build_target_df"
    )
    @mock.patch.object(services_module, "partition_has_data")
    def test_raises_when_schema_validation_fails(
        self,
        mock_partition_has_data,
        mock_build_target_df,
        mock_table_exists,
        mock_complete_schema,
        mock_get_versioning_df,
        mock_schema_validator_cls,
        cfg,
        pipeline_with_spec,
    ):
        # arrange
        mock_partition_has_data.return_value = False
        mock_table_exists.return_value = False

        non_empty_df = mock.MagicMock()
        non_empty_df.isEmpty.return_value = False
        table_df = mock.MagicMock()
        table_df.where.return_value = non_empty_df
        spark = mock.MagicMock()
        spark.table.return_value = table_df

        target_df = mock.MagicMock()
        mock_build_target_df.return_value = target_df

        versioned_df = mock.MagicMock()
        versioned_df.select.return_value = versioned_df
        mock_get_versioning_df.return_value = versioned_df
        mock_complete_schema.return_value = target_df

        validator = mock_schema_validator_cls.return_value
        validator.validate_schema.return_value = False

        pipeline = pipeline_with_spec

        # act / assert
        with pytest.raises(SchemaValidationError, match="Schema validation failed"):
            pipeline.create_core_model(spark)


class TestSupportJourneyServicesCoreModelPipelineRun:
    @mock.patch.object(
        services_module.SupportJourneyServicesCoreModelPipeline, "create_core_model"
    )
    @mock.patch.object(
        services_module.SupportJourneyServicesCoreModelPipeline,
        "initialize_spark_session",
    )
    @mock.patch.object(
        services_module.SupportJourneyServicesCoreModelPipeline,
        "initialize_configuration",
    )
    @mock.patch.object(services_module, "table_spec_from_cfg")
    def test_run_initializes_spark_and_executes_pipeline(
        self,
        mock_table_spec_from_cfg,
        mock_initialize_configuration,
        mock_initialize_spark_session,
        mock_create_core_model,
        cfg,
        table_spec,
    ):
        # arrange
        spark = mock.MagicMock()
        mock_initialize_spark_session.return_value = spark
        mock_table_spec_from_cfg.return_value = table_spec
        pipeline = services_module.SupportJourneyServicesCoreModelPipeline(cfg)

        # act
        pipeline.run()

        # assert
        mock_initialize_configuration.assert_called_once_with(cfg.dag_name)
        mock_table_spec_from_cfg.assert_called_once_with(cfg)
        mock_initialize_spark_session.assert_called_once()
        mock_create_core_model.assert_called_once_with(spark)
