from enum import Enum


class ShortCircuitFunctionEnum(Enum):

    CHECK_IS_FIRST_BUSINESS_DAY_OF_MONTH = "CHECK_IS_FIRST_BUSINESS_DAY_OF_MONTH"

    @classmethod
    def get_available_enum_values(cls):
        return [member.value for member in cls]

    @classmethod
    def get_function(cls, python_callable: str):

        from bietlejuice.base.airflow.dag_builders.main_builder.short_circuit_functions.dag_run_date_validators import (
            DAGRunDateValidators,
        )

        short_circuit_enum_member = cls(python_callable)

        return {
            cls.CHECK_IS_FIRST_BUSINESS_DAY_OF_MONTH: DAGRunDateValidators.check_is_first_business_day_of_month
        }.get(short_circuit_enum_member)
