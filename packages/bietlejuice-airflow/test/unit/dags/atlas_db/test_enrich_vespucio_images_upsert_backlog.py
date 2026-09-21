"""Unit tests for enrich_vespucio_images_upsert_backlog DAG helpers."""

from dags.atlas_db.enrich_vespucio_images_upsert_backlog import (
    enrich_vespucio_images_upsert_backlog as dag_module,
)


class TestBuildStepParameters:
    def test_omits_force_rebuild_flag_by_default(self):
        # Arrange / Act
        parameters = dag_module.build_step_parameters(False)

        # Assert
        assert "--force_rebuild" not in parameters
        assert parameters == dag_module.BUILD_STEP_BASE_PARAMETERS

    def test_appends_force_rebuild_flag_when_enabled(self):
        # Arrange / Act
        parameters = dag_module.build_step_parameters(True)

        # Assert
        assert parameters[:-1] == dag_module.BUILD_STEP_BASE_PARAMETERS
        assert parameters[-1] == "--force_rebuild"


class TestJobTasks:
    def test_build_includes_force_rebuild_when_requested(self):
        # Arrange / Act
        tasks = dag_module.job_tasks(
            rebuild=True,
            force_rebuild=True,
            dag_id="bietlejuice.enrich_vespucio_images_upsert_backlog",
            run_id="manual__2026-09-21",
        )

        # Assert
        build_task = tasks[0]
        assert build_task["task_key"] == dag_module.BUILD_STEP_TASK_ID
        assert "--force_rebuild" in build_task["python_wheel_task"]["parameters"]
