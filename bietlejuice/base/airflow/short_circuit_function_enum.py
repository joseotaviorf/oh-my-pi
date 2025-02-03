from enum import Enum


class ShortCircuitFunctionEnum(Enum):

    CHECK_IS_FIRST_BUSINESS_DAY_OF_MONTH = "CHECK_IS_FIRST_BUSINESS_DAY_OF_MONTH"
    CHECK_IS_SECOND_BUSINESS_DAY_OF_MONTH = "CHECK_IS_SECOND_BUSINESS_DAY_OF_MONTH"
    CHECK_IS_IN_RANGE_OF_DAYS = "CHECK_IS_IN_RANGE_OF_DAYS"
    CHECK_IS_IN_RANGE_OF_WEEKDAYS = "CHECK_IS_IN_RANGE_OF_WEEKDAYS"
    CHECK_IS_LAST_BUSINESS_DAY_OF_MONTH = "CHECK_IS_LAST_BUSINESS_DAY_OF_MONTH"
    CHECK_IS_SPECIFIC_DAY_OF_MONTH = "CHECK_IS_SPECIFIC_DAY_OF_MONTH"
    CHECK_IS_SPECIFIC_WEEKDAY = "CHECK_IS_SPECIFIC_WEEKDAY"

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
            cls.CHECK_IS_FIRST_BUSINESS_DAY_OF_MONTH: DAGRunDateValidators.check_is_first_business_day_of_month,
            cls.CHECK_IS_SECOND_BUSINESS_DAY_OF_MONTH: DAGRunDateValidators.check_is_second_business_day_of_month,
            cls.CHECK_IS_IN_RANGE_OF_DAYS: DAGRunDateValidators.check_is_in_range_of_days,
            cls.CHECK_IS_IN_RANGE_OF_WEEKDAYS: DAGRunDateValidators.check_is_in_range_of_weekdays,
            cls.CHECK_IS_LAST_BUSINESS_DAY_OF_MONTH: DAGRunDateValidators.check_is_last_business_day_of_month,
            cls.CHECK_IS_SPECIFIC_DAY_OF_MONTH: DAGRunDateValidators.check_is_specific_day_of_month,
            cls.CHECK_IS_SPECIFIC_WEEKDAY: DAGRunDateValidators.check_is_specific_weekday,
        }.get(short_circuit_enum_member)
