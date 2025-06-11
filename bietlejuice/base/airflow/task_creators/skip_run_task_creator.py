from airflow.operators.python_operator import ShortCircuitOperator
from bietlejuice.base.airflow.short_circuit_function_enum import (
    ShortCircuitFunctionEnum,
)
from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from databricks_plugin import QuintoAndarDatabricksCheckJobTaskOperator


class SkipRunTaskCreator(BaseTaskCreator):
    """
    Creates a short circuit operator task that checks if the downstream tasks should run using
    a function set in ShortCircuitFunctionEnum.
    """

    _TASK_ID_TEMPLATE = "check-day-to-skip-execution"

    def create_task(self) -> QuintoAndarDatabricksCheckJobTaskOperator:
        short_circuit_customization = self._get_short_circuit_customization()
        (parameters, function_params) = self._get_parameters(
            short_circuit_customization
        )

        return ShortCircuitOperator(
            dag=self.dag_execution_context.dag,
            task_id=self._TASK_ID_TEMPLATE,
            python_callable=ShortCircuitFunctionEnum.get_function(
                short_circuit_customization["function"]
            ),
            op_args=parameters,
            op_kwargs=function_params,
        )

    def _get_short_circuit_customization(self) -> dict:
        short_circuit_customization = self.dag_execution_context.workflow_args.get(
            "short_circuit_customization", ""
        )
        return short_circuit_customization

    def _get_parameters(self, short_circuit_customization: dict) -> tuple:
        execution_date = short_circuit_customization.get(
            "execution_date", "{{ data_interval_start | ds }}"
        )
        function_params = short_circuit_customization.get("function_params", {})

        return ([execution_date], function_params)
