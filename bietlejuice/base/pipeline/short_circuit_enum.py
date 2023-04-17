from enum import Enum


class ShortCircuitEnum(Enum):

    FIRST_BUSINESS_DAY_OF_MONTH = "FIRST_BUSINESS_DAY_OF_MONTH"

    @classmethod
    def get_available_enum_values(cls):
        return [member.value for member in cls]

    @classmethod
    def get_validate_type(cls, method: str, dag_execution_date: str):

        from bietlejuice.base.airflow.dag_builders.main_builder.short_circuit_functions.dag_run_date_validators import (
            DAGRunDateValidators,
        )

        short_circuit_enum_member = cls(method)

        return {
            cls.FIRST_BUSINESS_DAY_OF_MONTH: DAGRunDateValidators(
                dag_execution_date
            ).first_business_day_of_month
        }.get(short_circuit_enum_member)
