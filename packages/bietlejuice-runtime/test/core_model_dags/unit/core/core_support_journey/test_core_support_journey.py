"""Unit tests for core_support_journey Airflow DAG helpers."""

from datetime import datetime
from unittest.mock import MagicMock, patch

import pytest
import yaml


class TestListTableSpecsFromDir:
    def test_loads_yml_files_sorted_by_stem(
        self, tmp_path, core_support_journey_module
    ):
        (tmp_path / "b_table.yml").write_text("target_table: b\n", encoding="utf-8")
        (tmp_path / "a_table.yml").write_text("target_table: a\n", encoding="utf-8")

        specs = core_support_journey_module.list_table_specs_from_dir(tmp_path)

        assert [stem for stem, _ in specs] == ["a_table", "b_table"]
        assert specs[0][1]["target_table"] == "a"
        assert specs[1][1]["target_table"] == "b"

    def test_empty_yml_becomes_empty_dict(self, tmp_path, core_support_journey_module):
        (tmp_path / "cases.yml").write_text("", encoding="utf-8")

        specs = core_support_journey_module.list_table_specs_from_dir(tmp_path)

        assert specs == [("cases", {})]

    def test_raises_when_directory_missing(self, tmp_path, core_support_journey_module):
        missing = tmp_path / "tables"

        with pytest.raises(ValueError, match="does not exist"):
            core_support_journey_module.list_table_specs_from_dir(missing)


class TestGetDailyTargetLogicalDate:
    @pytest.mark.parametrize(
        "logical_date,execution_hour,expected",
        [
            (datetime(2026, 5, 27, 5, 30), 6, datetime(2026, 5, 26, 6, 0, 0)),
            (datetime(2026, 5, 27, 7, 0), 6, datetime(2026, 5, 27, 6, 0, 0)),
            (datetime(2026, 5, 27, 6, 0), 6, datetime(2026, 5, 27, 6, 0, 0)),
        ],
    )
    def test_aligns_to_previous_day_when_before_execution_hour(
        self, logical_date, execution_hour, expected, core_support_journey_module
    ):
        result = core_support_journey_module.get_daily_target_logical_date(
            logical_date, execution_hour
        )

        assert result == expected


class TestBuildDagExecutionContext:
    def test_attaches_job_cluster_engine(self, core_support_journey_module):
        dag = MagicMock()
        with patch.object(
            core_support_journey_module, "attach_job_cluster_engine_to_context"
        ) as mock_attach:
            ctx = core_support_journey_module.build_dag_execution_context(dag)

        assert ctx.dag is dag
        mock_attach.assert_called_once_with(
            ctx, core_support_journey_module.CONFIG_SERVICE
        )


class TestTableConfigRelativePath:
    def test_builds_s3_relative_path_under_dag_package(
        self, core_support_journey_module
    ):
        path = core_support_journey_module.table_config_relative_path("cases")

        assert path == "core/core_support_journey/tables/cases.yml"
        assert len(path) < 256


class TestCreateLoadTableTask:
    def test_builds_spark_task_with_parsed_parameters(
        self, core_support_journey_module
    ):
        mock_engine = core_support_journey_module._mock_engine
        mock_engine.create_spark_python_task.reset_mock()
        ctx = MagicMock()
        ctx.job_cluster_engine = mock_engine

        task = core_support_journey_module.create_load_table_task(ctx, "cases")

        mock_engine.create_spark_python_task.assert_called_once()
        call_kwargs = mock_engine.create_spark_python_task.call_args.kwargs
        assert call_kwargs["task_id"] == "load_core_support_journey_cases"
        assert "core_model/support_journey/cases.py" in call_kwargs["spark_job_path"]

        job_parameters = call_kwargs["job_parameters"]
        params = dict(zip(job_parameters[::2], job_parameters[1::2]))
        assert params["--target_schema"] == "core_support_journey"
        assert params["--target_table"] == "cases"
        assert params["--job_name"] == "load_core_support_journey_cases"
        assert (
            params["--table_config_relative_path"]
            == "core/core_support_journey/tables/cases.yml"
        )
        assert task.task_id == "load_core_support_journey_cases"


class TestCreateExecuteJobClusterTask:
    def test_delegates_to_job_cluster_engine(self, core_support_journey_module):
        mock_engine = core_support_journey_module._mock_engine
        mock_engine.create_execute_cluster_task.reset_mock()
        ctx = MagicMock()
        ctx.job_cluster_engine = mock_engine

        core_support_journey_module.create_execute_job_cluster_task(ctx)

        mock_engine.create_execute_cluster_task.assert_called_once()


class TestDagModuleConstants:
    def test_dag_id_and_schema(self, core_support_journey_module):
        assert core_support_journey_module.DAG_ID == "bietlejuice.core_support_journey"
        assert core_support_journey_module.CORE_SCHEMA == "core_support_journey"

    def test_tables_dir_points_to_repo_tables_folder(self, core_support_journey_module):
        tables_dir = core_support_journey_module.TABLES_DIR
        assert tables_dir.is_dir()
        assert (tables_dir / "cases.yml").is_file()
        loaded = yaml.safe_load((tables_dir / "cases.yml").read_text(encoding="utf-8"))
        assert loaded["target_table"] == "cases"
