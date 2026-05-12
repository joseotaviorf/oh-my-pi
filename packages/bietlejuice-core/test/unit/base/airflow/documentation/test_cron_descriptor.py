import pytest

# from unittest import mock
from bietlejuice.base.airflow.documentation import CronDescriptor


class TestCronDescriptor:
    def test_get_description(self):
        # arrange
        expression = "10-55 * * * *"
        expected_return = "Minutes 10 through 55 past the hour"

        # act
        returned_value = CronDescriptor.get_description(expression=expression)

        # assert
        assert returned_value == expected_return

    @pytest.mark.parametrize(
        "expression_params",
        [
            ["*", "*", "Every minute"],
            ["30", "*", "At 30 minutes past the hour"],
            ["*", "2", "Every minute, between 02:00 AM and 02:59 AM"],
            ["3", "2-3", "At 3 minutes past the hour, between 02:00 AM and 03:59 AM"],
            [
                "3,5",
                "2",
                "At 3 and 5 minutes past the hour, between 02:00 AM and 02:59 AM",
            ],
            ["3-5", "2", "Every minute between 02:03 AM and 02:05 AM"],
            ["30", "2", "At 02:30 AM"],
        ],
    )
    def test_interval_time_description(self, expression_params):
        # arrange
        minute_expression = expression_params[0]
        hour_expression = expression_params[1]
        expected_return = expression_params[2]

        # act
        returned_value = CronDescriptor._interval_time_description(
            minute_expression=minute_expression, hour_expression=hour_expression
        )

        # assert
        assert returned_value == expected_return

    @pytest.mark.parametrize(
        "expression_params",
        [
            ["minute", "At 2 minutes past the hour"],
            ["hour", "between 02:00 AM and 02:59 AM"],
            ["day", "on day 2 of the month"],
            ["month", "only in February"],
            ["week_day", "only on Tuesday"],
        ],
    )
    def test_interval_description(self, expression_params):
        # arrange
        expression = "2"
        expression_type = expression_params[0]
        expected_return = expression_params[-1]

        # act
        returned_value = CronDescriptor._interval_description(
            expression=expression, expression_type=expression_type
        )

        # assert
        assert returned_value == expected_return

    @pytest.mark.parametrize(
        "expression_params",
        [
            ["minute", "At 2 through 3 and 5 minutes past the hour"],
            ["hour", "at 02:00 AM through 03:59 AM and 05:00 AM"],
            ["day", "on day 2 through 3 and 5 of the month"],
            ["month", "only in February through March and May"],
            ["week_day", "only on Tuesday through Wednesday and Friday"],
        ],
    )
    def test_interval_description_multiple_intervals(self, expression_params):
        # arrange
        expression = "2-3,5"
        expression_type = expression_params[0]
        expected_return = expression_params[-1]

        # act
        returned_value = CronDescriptor._interval_description(
            expression=expression, expression_type=expression_type
        )

        # assert
        assert returned_value == expected_return

    @pytest.mark.parametrize(
        "expression_params",
        [
            ["minute", None],
            ["hour", None],
            ["day", None],
            ["month", "February"],
            ["week_day", "Tuesday"],
        ],
    )
    def test_convert_expression_number(self, expression_params):
        # arrange
        expression_number = "2"
        expression_type = expression_params[0]
        expected_return = (
            expression_params[-1] if expression_params[-1] else expression_number
        )

        # act
        returned_value = CronDescriptor._convert_expression_number(
            expression_number=expression_number, expression_type=expression_type
        )

        # assert
        assert returned_value == expected_return

    @pytest.mark.parametrize(
        "expression_params",
        [
            [True, "2", "30", "02:30 AM"],
            [True, "2", None, "02:00 AM"],
            [False, "2", None, "02:59 AM"],
            [False, "2", "30", "02:30 AM"],
        ],
    )
    def test_format_hour_minute(self, expression_params):
        # arrange
        first_position = expression_params[0]
        hour_expression = expression_params[1]
        minute_expression = expression_params[2]
        expected_return = expression_params[3]

        # act
        returned_value = CronDescriptor._format_hour_minute(
            hour_expression=hour_expression,
            minute_expression=minute_expression,
            first_position=first_position,
        )

        # assert
        assert returned_value == expected_return
