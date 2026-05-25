import logging
from datetime import datetime

from airflow.decorators import dag, task
from airflow.models import DagRun, TaskInstance  # <-- Import TaskInstance
from airflow.utils.session import provide_session
from airflow.utils.state import (
    DagRunState,
    TaskInstanceState,
)  # <-- Import TaskInstanceState
from pendulum import timezone

logger = logging.getLogger(__name__)


@provide_session
def find_and_fail_active_runs_and_tis(session=None):
    """
    Finds all DAG runs in 'running' or 'queued' state and marks them,
    and their unfinished task instances, as 'failed'.
    """
    logger.info("Starting query for active ('running' or 'queued') DAG runs...")

    # Find active DAG runs
    active_runs = (
        session.query(DagRun)
        .filter(DagRun.state.in_([DagRunState.RUNNING, DagRunState.QUEUED]))
        .all()
    )

    if not active_runs:
        logger.info("No active (running or queued) DAG runs found.")
        return

    logger.warning(
        f"Found {len(active_runs)} active DAG runs. Marking them and their tasks as FAILED..."
    )

    count_success = 0
    count_fail = 0

    for run in active_runs:
        if run.dag_id == "fail_active_dag_runs_and_tasks":
            logger.info(f"Skipping self DAG run: {run.dag_id} | {run.run_id}")
            continue
        try:
            logger.info(f"Processing DAG Run: {run.dag_id} | {run.run_id}")

            # Find and fail active/unfinished task instances for this run first
            logger.info(f"Querying for unfinished tasks for run: {run.run_id}")
            active_tis = (
                session.query(TaskInstance)
                .filter(
                    TaskInstance.dag_id == run.dag_id,
                    TaskInstance.run_id == run.run_id,
                    TaskInstance.state.in_(
                        [
                            TaskInstanceState.RUNNING,
                            TaskInstanceState.QUEUED,
                            TaskInstanceState.SCHEDULED,
                            TaskInstanceState.UP_FOR_RETRY,
                            TaskInstanceState.UP_FOR_RESCHEDULE,
                        ]
                    ),
                )
                .all()
            )

            if active_tis:
                logger.warning(
                    f"Found {len(active_tis)} unfinished tasks. Marking them as FAILED..."
                )
                for ti in active_tis:
                    try:
                        logger.info(
                            f"  - Marking TI as FAILED: {ti.task_id} | State: {ti.state}"
                        )
                        # Set task instance state to FAILED
                        ti.set_state(TaskInstanceState.FAILED, session=session)
                    except Exception as ti_e:
                        logger.error(
                            f"    Error marking TI {ti.task_id} as FAILED: {ti_e}"
                        )
            else:
                logger.info("No unfinished tasks found for this run.")

            # Now, mark the DAG run itself as FAILED
            logger.info(f"Marking DAG Run as FAILED: {run.dag_id} | {run.run_id}")
            run.set_state(DagRunState.FAILED)

            count_success += 1

        except Exception as e:
            logger.error(f"Error processing DAG run {run.dag_id} | {run.run_id}: {e}")
            count_fail += 1

    logger.info(f"Cleanup complete. Successfully processed {count_success} DAG runs.")
    if count_fail > 0:
        logger.warning(f"Failed to process {count_fail} DAG runs.")


@dag(
    # Updated dag_id for clarity
    dag_id="fail_active_dag_runs_and_tasks",
    start_date=datetime(2025, 1, 1, tzinfo=timezone("America/Sao_Paulo")),
    schedule="50 20 * * *",
    catchup=False,
    tags=["maintenance", "cleanup"],  # Added tags
)
def fail_active_runs_and_tasks_dag():
    """
    A maintenance DAG that finds all running or queued DAG runs and
    marks them and their unfinished tasks as FAILED.
    """

    @task
    def fail_runs_and_tasks_task():
        """Calls the main cleanup function."""
        find_and_fail_active_runs_and_tis()

    fail_runs_and_tasks_task()


# Instantiate the DAG
fail_active_runs_and_tasks_dag()
