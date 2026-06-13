"""Unit tests for SupportJourneyCoreModelPipeline (cases table)."""

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
    cases as cases_module,
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
    spec_path = _find_project_root() / "dags/core/core_support_journey/tables/cases.yml"
    return yaml.safe_load(spec_path.read_text(encoding="utf-8"))


@pytest.fixture
def cfg(table_spec):
    return SimpleNamespace(
        job_name="load_core_support_journey_cases",
        dag_name="core_support_journey",
        partition_date="2026-05-27",
        partition_hour="14",
        bucket="test-bucket",
        table_config_json=json.dumps(table_spec),
    )


@pytest.fixture
def pipeline_with_spec(cfg, table_spec):
    pipeline = cases_module.SupportJourneyCoreModelPipeline(cfg)
    pipeline.table_spec = table_spec_from_cfg(cfg)
    # Mirror run_config(): populate tracked_cols from the source specs so
    # create_core_model() can read self.tracked_cols["case"] directly.
    pipeline.tracked_cols = {
        table: source["tracked_cols"]
        for table, source in pipeline.table_spec["sources"].items()
        if source.get("tracked_cols")
    }
    return pipeline


class TestSupportJourneyCoreModelPipelineInit:
    def test_table_spec_loaded_from_json_string(self, cfg, table_spec):
        spec = table_spec_from_cfg(cfg)

        assert spec["target_table"] == table_spec["target_table"]
        assert spec["merge_on"] == table_spec["merge_on"]

    def test_table_spec_accepts_dict_config(self, table_spec):
        cfg = SimpleNamespace(
            job_name="load_core_support_journey_cases",
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
            table_config_relative_path="core/core_support_journey/tables/cases.yml"
        )

        assert table_spec_from_cfg(cfg) == table_spec
        mock_load.assert_called_once_with("core/core_support_journey/tables/cases.yml")


class TestSupportJourneyCoreModelPipelineCreateCoreModel:
    @mock.patch.object(cases_module, "partition_has_data")
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
            spark, "core_support_journey.cases", cfg.partition_date, cfg.partition_hour
        )
        spark.table.assert_not_called()

    @mock.patch.object(cases_module, "filter_relevant_cdc_events")
    @mock.patch.object(cases_module, "partition_has_data")
    def test_returns_when_filtered_case_partition_is_empty(
        self, mock_partition_has_data, mock_filter, cfg, pipeline_with_spec
    ):
        # arrange
        spark = mock.MagicMock()
        source_df = mock.MagicMock()
        spark.table.return_value.where.return_value = source_df

        filtered_df = mock.MagicMock()
        filtered_df.isEmpty.return_value = True
        mock_filter.return_value.dropDuplicates.return_value = filtered_df
        mock_partition_has_data.return_value = False
        pipeline = pipeline_with_spec

        # act
        pipeline.create_core_model(spark)

        # assert
        spark.table.assert_called_once_with(
            pipeline.table_spec["sources"]["case"]["table_name"]
        )
        mock_filter.assert_called_once_with(source_df, pipeline.tracked_cols["case"])
        filtered_df.isEmpty.assert_called_once()

    @mock.patch.object(cases_module, "filter_relevant_cdc_events")
    @mock.patch.object(cases_module, "DataFrameDeltaTableLoaderPipeline")
    @mock.patch.object(cases_module, "SchemaValidator")
    @mock.patch.object(cases_module, "get_versioning_df")
    @mock.patch.object(cases_module, "_complete_dataframe_schema")
    @mock.patch.object(cases_module, "_table_exists")
    @mock.patch.object(cases_module, "get_latest_version_from_df")
    @mock.patch.object(cases_module, "partition_has_data")
    def test_runs_delta_pipeline_when_schema_is_valid(
        self,
        mock_partition_has_data,
        mock_get_latest_version,
        mock_table_exists,
        mock_complete_schema,
        mock_get_versioning_df,
        mock_schema_validator_cls,
        mock_pipeline_cls,
        mock_filter,
        cfg,
        pipeline_with_spec,
    ):
        # arrange
        mock_partition_has_data.return_value = False
        mock_table_exists.return_value = False
        mock_get_latest_version.side_effect = lambda df, *_args, **_kwargs: df

        source_df = mock.MagicMock()
        source_df.isEmpty.return_value = False
        source_df.withColumn.return_value = source_df
        source_df.alias.return_value = source_df
        source_df.join.return_value = source_df
        source_df.select.return_value = source_df
        mock_filter.return_value.dropDuplicates.return_value = source_df

        spark = mock.MagicMock()
        spark.table.return_value.where.return_value = source_df

        versioned_df = mock.MagicMock()
        versioned_df.select.return_value = versioned_df
        mock_get_versioning_df.return_value = versioned_df
        mock_complete_schema.return_value = source_df

        validator = mock_schema_validator_cls.return_value
        validator.validate_schema.return_value = True

        mock_pipeline = mock_pipeline_cls.return_value
        pipeline = pipeline_with_spec

        # act
        pipeline.create_core_model(spark)

        # assert
        mock_filter.assert_called_once_with(source_df, pipeline.tracked_cols["case"])
        mock_pipeline_cls.assert_called_once()
        mock_pipeline.run.assert_called_once()

    @mock.patch.object(cases_module, "filter_relevant_cdc_events")
    @mock.patch.object(cases_module, "SchemaValidator")
    @mock.patch.object(cases_module, "get_versioning_df")
    @mock.patch.object(cases_module, "_complete_dataframe_schema")
    @mock.patch.object(cases_module, "_table_exists")
    @mock.patch.object(cases_module, "get_latest_version_from_df")
    @mock.patch.object(cases_module, "partition_has_data")
    def test_raises_when_schema_validation_fails(
        self,
        mock_partition_has_data,
        mock_get_latest_version,
        mock_table_exists,
        mock_complete_schema,
        mock_get_versioning_df,
        mock_schema_validator_cls,
        mock_filter,
        cfg,
        pipeline_with_spec,
    ):
        # arrange
        mock_partition_has_data.return_value = False
        mock_table_exists.return_value = False
        mock_get_latest_version.side_effect = lambda df, *_args, **_kwargs: df

        source_df = mock.MagicMock()
        source_df.isEmpty.return_value = False
        source_df.withColumn.return_value = source_df
        source_df.alias.return_value = source_df
        source_df.join.return_value = source_df
        source_df.select.return_value = source_df
        mock_filter.return_value.dropDuplicates.return_value = source_df

        spark = mock.MagicMock()
        spark.table.return_value.where.return_value = source_df

        versioned_df = mock.MagicMock()
        versioned_df.select.return_value = versioned_df
        mock_get_versioning_df.return_value = versioned_df
        mock_complete_schema.return_value = source_df

        validator = mock_schema_validator_cls.return_value
        validator.validate_schema.return_value = False

        pipeline = pipeline_with_spec

        # act / assert
        with pytest.raises(SchemaValidationError, match="Schema validation failed"):
            pipeline.create_core_model(spark)


class TestSupportJourneyCoreModelPipelineRun:
    @mock.patch.object(
        cases_module.SupportJourneyCoreModelPipeline, "create_core_model"
    )
    @mock.patch.object(
        cases_module.SupportJourneyCoreModelPipeline, "initialize_spark_session"
    )
    @mock.patch.object(
        cases_module.SupportJourneyCoreModelPipeline, "initialize_configuration"
    )
    @mock.patch.object(cases_module, "table_spec_from_cfg")
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
        pipeline = cases_module.SupportJourneyCoreModelPipeline(cfg)

        # act
        pipeline.run()

        # assert
        mock_initialize_configuration.assert_called_once_with(cfg.dag_name)
        mock_table_spec_from_cfg.assert_called_once_with(cfg)
        mock_initialize_spark_session.assert_called_once()
        mock_create_core_model.assert_called_once_with(spark)
        # run_config() should load tracked_cols for sources that declare them
        assert (
            pipeline.tracked_cols["case"]
            == table_spec["sources"]["case"]["tracked_cols"]
        )

    @mock.patch.object(
        cases_module.SupportJourneyCoreModelPipeline, "initialize_spark_session"
    )
    @mock.patch.object(
        cases_module.SupportJourneyCoreModelPipeline, "initialize_configuration"
    )
    @mock.patch.object(cases_module, "table_spec_from_cfg")
    def test_run_config_only_tracks_sources_that_declare_tracked_cols(
        self,
        mock_table_spec_from_cfg,
        mock_initialize_configuration,
        mock_initialize_spark_session,
        cfg,
        table_spec,
    ):
        # arrange
        mock_table_spec_from_cfg.return_value = table_spec
        pipeline = cases_module.SupportJourneyCoreModelPipeline(cfg)

        # act
        pipeline.run_config()

        # assert
        sources = table_spec["sources"]
        expected = {
            table: source["tracked_cols"]
            for table, source in sources.items()
            if source.get("tracked_cols")
        }
        assert pipeline.tracked_cols == expected
        # sources without tracked_cols must not leak into the dict
        assert "record_types" not in pipeline.tracked_cols
        assert "case_milestones" not in pipeline.tracked_cols
