from datetime import timedelta
from typing import Callable, Collection, Optional

from airflow.exceptions import AirflowException
from airflow.models import DagModel
from airflow.sensors.external_task import ExternalTaskSensor
from airflow.utils.session import provide_session

"""
## SStExternalTaskSensor parameters and working mode

`SStExternalTaskSensor` wraps Airflow's `ExternalTaskSensor` with SST defaults.

By default, the sensor:

* checks the external dependency every 30 minutes
* waits up to 2 hours before timing out
* retries up to 3 times if the sensor execution fails
* uses `delta_hours` to calculate which upstream logical date should be checked
* supports custom execution date logic through `execution_date_fn`

### Parameters

| Parameter | Description |
|---|---|
| `external_dag_id` | The external DAG that this sensor should wait for. |
| `external_task_id` | A single external task to wait for. |
| `external_task_ids` | Multiple external tasks to wait for. |
| `timeout` | Maximum amount of time the sensor can wait before failing. Default is 2 hours. |
| `delta_hours` | Hours to subtract from the current logical date when checking the external DAG/task. |
| `execution_timeout` | Maximum time allowed for each sensor execution attempt. Default is 10 minutes. |
| `poke_interval` | How often the sensor checks the external dependency. Default is 30 minutes. |
| `execution_date_fn` | Optional function to resolve the external logical date(s). If provided, `delta_hours` is ignored. |
| `retries` | Number of retries if the sensor task fails. Default is 3. |
| `retry_delay` | Delay between retries. Default is 5 minutes. |
| `retry_exponential_backoff` | If enabled, increases the retry delay after each failed attempt. |

### Execution date behavior

If `execution_date_fn` is provided, `execution_delta` is not passed to the parent sensor.

If `execution_date_fn` is not provided, `delta_hours` is converted to `execution_delta` (or left unset when `delta_hours` is `None`).
"""


class SStExternalTaskSensor(ExternalTaskSensor):
    """
    Thin wrapper around Airflow's ExternalTaskSensor with SST defaults.

    Defaults:
        - Runs in reschedule mode to avoid occupying a worker slot between pokes.
        - Uses a 2-hours timeout.
        - Uses a 30-minute poke interval.
        - Uses a 10-minute execution timeout per task attempt.
        - Fails immediately when the external DAG is paused.

    Args:
        external_dag_id: DAG ID that contains the external task being sensed.
        external_task_id: Single external task ID to wait for.
        external_task_ids: Collection of external task IDs to wait for.
        timeout: Maximum total sensor runtime in seconds.
        delta_hours: Difference in logical date between current DAG and external DAG.
        execution_timeout: Maximum runtime for each task execution attempt.
        poke_interval: Time in seconds between each sensor poke.
        execution_date_fn: Function that returns the logical date or dates to query.
            If provided, delta_hours is ignored.
        retries: Number of retries after task failure.
        retry_delay: Delay between retries.
        retry_exponential_backoff: Whether to exponentially increase retry delay.

    Usage:

    * Task Sensor:
        wait_for_upstream = SStExternalTaskSensor(
            task_id="wait_for_upstream_dag",
            external_dag_id="upstream_dag_id",
            external_task_id="upstream_task_id",
            delta_hours=1,
        )

    * Full DAG sensor:
        wait_for_upstream = SStExternalTaskSensor(
            task_id="wait_for_upstream_dag",
            external_dag_id="upstream_dag_id",
            delta_hours=24,
        )

    * Multiple Tasks Sensor:
        wait_for_upstream_tasks = SStExternalTaskSensor(
            task_id="wait_for_upstream_tasks",
            external_dag_id="upstream_dag_id",
            external_task_ids=[
                "task_a",
                "task_b",
                "task_c",
            ],
            delta_hours=1,
        )
    """

    def __init__(
        self,
        external_dag_id: str,
        external_task_id: Optional[str] = None,
        external_task_ids: Optional[Collection[str]] = None,
        timeout: int = (60 * 60 * 2),  # 2 hours timeout
        delta_hours: Optional[float] = None,
        execution_timeout: timedelta = timedelta(seconds=60 * 10),  # 10 minute timeout
        poke_interval: int = (60 * 30),  # 30 minutes
        execution_date_fn: Optional[Callable] = None,
        retries: int = 3,
        retry_delay: timedelta = timedelta(minutes=5),
        retry_exponential_backoff: bool = True,
        *args,
        **kwargs,
    ):

        if execution_date_fn:
            execution_delta = None
        elif delta_hours is None:
            execution_delta = None
        else:
            execution_delta = timedelta(hours=delta_hours)

        assert execution_date_fn is None or execution_delta is None

        super().__init__(
            external_task_id=external_task_id,
            external_dag_id=external_dag_id,
            external_task_ids=external_task_ids,
            timeout=timeout,
            execution_delta=execution_delta,
            execution_timeout=execution_timeout,
            poke_interval=poke_interval,
            execution_date_fn=execution_date_fn,
            retries=retries,
            retry_delay=retry_delay,
            retry_exponential_backoff=retry_exponential_backoff,
            mode="reschedule",
            *args,
            **kwargs,
        )

    def _is_external_dag_paused(self, session):
        dag = (
            session.query(DagModel)
            .filter(DagModel.dag_id == self.external_dag_id)
            .first()
        )

        return dag and dag.get_is_paused()

    @provide_session
    def poke(self, context, session=None):
        if self._is_external_dag_paused(session):
            raise AirflowException(
                f"DAG {self.external_dag_id} is paused. Cannot sense on a paused DAG."
            )

        return super().poke(context)
