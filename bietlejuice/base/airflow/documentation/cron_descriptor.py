from datetime import datetime


class CronDescriptor:
    """
    This class contains methods for converting cron expressions into human readable strings.
    """

    WEEK_DAYS_DESCRIPTION = [
        "Sunday",
        "Monday",
        "Tuesday",
        "Wednesday",
        "Thursday",
        "Friday",
        "Saturday",
        "Sunday",
    ]

    MINUTE = {
        "multiple_intervals_prefix": "At ",
        "multiple_intervals_sufix": " minutes past the hour",
    }
    HOUR = {"multiple_intervals_prefix": "at "}
    DAY = {
        "multiple_intervals": "{first_expression} through {last_expression}",
        "simple_interval": "between day {first_expression} and {last_expression} of the month",
        "without_intervals": "on day {first_expression} of the month",
        "multiple_intervals_prefix": "on day ",
        "multiple_intervals_sufix": " of the month",
    }

    WEEK_DAY = {
        "multiple_intervals": "{first_expression} through {last_expression}",
        "simple_interval": "{first_expression} through {last_expression}",
        "without_intervals": "only on {first_expression}",
        "multiple_intervals_prefix": "only on ",
    }

    MONTH = {
        "multiple_intervals": "{first_expression} through {last_expression}",
        "simple_interval": "{first_expression} through {last_expression}",
        "without_intervals": "only in {first_expression}",
        "multiple_intervals_prefix": "only in ",
    }

    @classmethod
    def get_description(self, expression):
        """
        This method returns the conversion of a cron expression to a natural language description.
        @param expression: str. Cron expression.
        @return: str.
        """
        expression_list = expression.split(" ")

        minute_expression = expression_list[0]
        hour_expression = expression_list[1]
        day_expression = expression_list[2]
        month_expression = expression_list[3]
        week_day_expression = expression_list[4]

        time_description = self._interval_time_description(
            minute_expression, hour_expression
        )

        day_description = self._interval_description(
            day_expression, expression_type="day"
        )
        month_description = self._interval_description(
            month_expression, expression_type="month"
        )
        week_day_description = self._interval_description(
            week_day_expression, expression_type="week_day"
        )

        cron_description = time_description
        if day_description:
            cron_description = f"{cron_description}, {day_description}"
        if week_day_description:
            cron_description = f"{cron_description}, {week_day_description}"
        if month_description:
            cron_description = f"{cron_description}, {month_description}"

        return cron_description

    @classmethod
    def _interval_description(self, expression, expression_type, **kwargs):
        """
        Identifies the type of interval configured in cron and returns its description.
        @param expression: str. Cron expression.
        @param expression_type: str. Cron expression type, example: day, month, etc.
        @return: str.
        """
        expression_list = expression.split(",")

        if expression_type == "minute":
            get_description = self._get_minute_description
            params = self.MINUTE
        elif expression_type == "hour":
            get_description = self._get_hour_description
            params = self.HOUR
        else:
            get_description = self._get_month_week_day_description
            if expression_type == "day":
                params = self.DAY
                kwargs = {
                    "expression_type": expression_type,
                    "description_params": params,
                    **kwargs,
                }
            elif expression_type == "month":
                params = self.MONTH
                kwargs = {
                    "expression_type": expression_type,
                    "description_params": params,
                    **kwargs,
                }
            elif expression_type == "week_day":
                params = self.WEEK_DAY
                kwargs = {
                    "expression_type": expression_type,
                    "description_params": params,
                    **kwargs,
                }

        prefix = params.get("multiple_intervals_prefix") or ""
        sufix = params.get("multiple_intervals_sufix") or ""

        if len(expression_list) == 1:
            description = get_description(expression, **kwargs)
        else:
            description = list(
                map(
                    lambda expression: get_description(
                        expression, has_multiple_intervals=True, **kwargs
                    ),
                    expression_list,
                )
            )
            description = f"{prefix}{self._join_descriptions(description)}{sufix}"

        return description

    @staticmethod
    def _join_descriptions(description_list, separator=","):
        """
        Unites different ranges into a single natural language text.
        @param description_list: List with descriptions of intervals to be joined.
        @param separator: A separator between Cron descriptions.
        @return: str.
        """

        join_description = (
            f"{f'{separator} '.join(description_list[0:-1])} and {description_list[-1]}"
            if len(description_list) > 1
            else description_list[0]
        )
        return join_description

    @classmethod
    def _get_month_week_day_description(
        self,
        expression,
        expression_type,
        description_params,
        has_multiple_intervals=False,
    ):
        """
        Formats day, month and day of week expressions to a corresponding description in natural language,
        considering the types of intervals defined in Cron.
        @param expression: str. Cron expression.
        @param expression_type: str. Cron expression type, example: day, month, etc.
        @param has_multiple_intervals: Cron can be configured in several intervals, this parameter indicates
            the presence of multiples. Ex: For Cron "* * 2,5-6 * *" we have several day intervals;
            For the case "* * 2-5 * *" we have a simple range of days, where this boolean must have a value of False.
        @param description_params: Contains standard descriptions for each type of expression. These descriptions
            are formatted to return the converted expression.
        @return: str.
        """
        if expression == "*":
            description = ""
        else:
            expression_list = [
                self._convert_expression_number(expression_number, expression_type)
                for expression_number in expression.split("-")
            ]

            if len(expression_list) > 1:
                multiple_intervals = description_params.get("multiple_intervals")
                simple_interval = description_params.get("simple_interval")
                description = (
                    multiple_intervals.format(
                        first_expression=expression_list[0],
                        last_expression=expression_list[-1],
                    )
                    if multiple_intervals
                    else simple_interval.format(
                        first_expression=expression_list[0],
                        last_expression=expression_list[-1],
                    )
                )
            else:
                without_intervals = description_params.get("without_intervals")
                description = (
                    expression_list[0]
                    if has_multiple_intervals
                    else without_intervals.format(first_expression=expression_list[0])
                )
        return description

    @classmethod
    def _convert_expression_number(self, expression_number, expression_type):
        """
        Converts a number to its corresponding description. Example: expression "1" of
        type month will return the value "January".
        @param expression_number: str. The number to be converted.
        @param expression_type: str. Cron expression type, example: day, month, etc.
        @return: str.
        """
        if expression_type == "month":
            return datetime.strptime(expression_number, "%m").strftime("%B")
        elif expression_type == "week_day":
            return self.WEEK_DAYS_DESCRIPTION[int(expression_number)]
        else:
            return expression_number

    @classmethod
    def _interval_time_description(self, minute_expression, hour_expression):
        """
        Identifies the type of interval configured in cron and returns its description, only for
        minutes and hours (time), since these types require more specific transcriptions in natural language.
        @param minute_expression: str. Cron minute expression.
        @param hour_expression: str. Cron hour expression.
        @return: str.
        """
        hour_description = self._interval_description(
            hour_expression, expression_type="hour"
        )
        minute_description = self._interval_description(
            minute_expression, expression_type="minute"
        )

        if minute_expression == "*" and hour_expression == "*":
            time_description = "Every minute"
        elif minute_expression != "*" and hour_expression == "*":
            time_description = minute_description
        elif minute_expression == "*" and hour_expression != "*":
            time_description = f"Every minute, {hour_description}"
        else:
            hour_list = hour_expression.split("-")
            minute_list = minute_expression.split("-")
            if len(hour_list) > 1 or len(minute_expression.split(",")) > 1:
                time_description = f"{minute_description}, {hour_description}"
            elif len(minute_list) > 1:
                time_description = f"Every minute {self._interval_description(hour_expression, expression_type='hour', minute_expression=minute_expression)}"
            else:
                time_description = f"At {self._interval_description(hour_expression, expression_type='hour', minute_expression=minute_expression, has_last_hour_position=False)}"
        return time_description

    @classmethod
    def _get_hour_description(
        self,
        hour_expression,
        minute_expression=None,
        has_last_hour_position=True,
        has_multiple_intervals=False,
    ):
        """
        Formats time expressions to a corresponding natural language description.
        @param hour_expression: str. Cron hour expression.
        @param minute_expression: str. Cron minute expression.
        @param has_last_hour_position: str. Identifies whether the time falls within a specific
            hour-minute interval. Example: For "* 2 * * *", the trigger occurs between 02:00 AM
            and 02:59 AM, so this parameter receives True value. For "30 5 * * *" the trigger only
            occurs at 05:30 AM, so this parameter receives the value False.
        @param has_multiple_intervals: Cron can be configured in several intervals, this parameter indicates
            the presence of multiples. Ex: For Cron "* 2,5-6 * * *" we have several time intervals;
            For the case "* 2-5 * * *" we have a simple time range, where this boolean must have a value of False.
        @return: str.
        """
        if hour_expression != "*":
            hour_list = hour_expression.split("-")
            minute_list = minute_expression.split("-") if minute_expression else [None]
            first_hour_position = self._format_hour_minute(hour_list[0], minute_list[0])
            if has_last_hour_position and (
                has_multiple_intervals is False or hour_list[0] != hour_list[-1]
            ):
                last_hour_position = self._format_hour_minute(
                    hour_list[-1], minute_list[-1], first_position=False
                )
                hour_description = (
                    f"{first_hour_position} through {last_hour_position}"
                    if has_multiple_intervals
                    else f"between {first_hour_position} and {last_hour_position}"
                )
            else:
                hour_description = f"{first_hour_position}"
            return hour_description

    @staticmethod
    def _get_minute_description(minute_expression, has_multiple_intervals=False):
        """
        Formats minute expressions to a corresponding natural language description.
        @param minute_expression: str. Cron minute expression.
        @param has_multiple_intervals: Cron can be configured in several intervals, this parameter indicates
            the presence of multiples. Ex: For Cron "2,5-6 * * * *" we have several minute intervals;
            For the case "2-5 * * * *" we have a simple minute interval, where this boolean must have a value of False.
        @return: str.
        """
        if minute_expression != "*":
            minute_list = minute_expression.split("-")
            if len(minute_list) > 1:
                minute_description = (
                    f"{minute_list[0]} through {minute_list[1]}"
                    if has_multiple_intervals
                    else f"Minutes {minute_list[0]} through {minute_list[1]} past the hour"
                )
            else:
                minute_description = (
                    minute_list[0]
                    if has_multiple_intervals
                    else f"At {minute_list[0]} minutes past the hour"
                )
            return minute_description

    @staticmethod
    def _format_hour_minute(
        hour_expression, minute_expression=None, first_position=True
    ):
        """
        Formats the hour and minute to a corresponding description. Example: 5 hours and 30 minutes is formatted for "05:30 AM".
        @param hour_expression: str. Number corresponding to hour expression.
        @param minute_expression: str. Number corresponding to minute expression.
        @param first_position: Indicates whether we are dealing with the beginning or end of a time interval. This will help to
            set the corresponding minute values when this is not defined by the Cron expression.
        @return: str.
        """

        hour_expression = (
            f"0{hour_expression}" if len(hour_expression) == 1 else hour_expression
        )

        day_period = "PM" if int(hour_expression) > 11 else "AM"
        if minute_expression:
            minute_expression = (
                f"0{minute_expression}"
                if int(minute_expression) < 10
                else minute_expression
            )
        elif first_position:
            minute_expression = "00"
        else:
            minute_expression = "59"

        hour_description = f"{hour_expression}:{minute_expression} {day_period}"
        return hour_description
