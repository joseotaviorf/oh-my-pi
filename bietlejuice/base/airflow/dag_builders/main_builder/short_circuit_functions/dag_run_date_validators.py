from datetime import datetime, date


class DAGRunDateValidators:
    @staticmethod
    def get_business_days_in_month(reference_date):
        from calendar import monthcalendar
        from workalendar.america import BrazilSaoPauloCity

        reference_datetime = datetime.strptime(reference_date, "%Y-%m-%d")
        ref_year, ref_month = reference_datetime.year, reference_datetime.month
        holidays_list = (
            holiday[0] for holiday in BrazilSaoPauloCity().holidays(ref_year)
        )
        weeks_list = [
            [d for d in w[:5] if d] for w in monthcalendar(ref_year, ref_month)
        ]
        business_dates_in_month = [
            date(ref_year, ref_month, day)
            for week in weeks_list
            for day in week
            if date(ref_year, ref_month, day) not in holidays_list
        ]
        return business_dates_in_month

    @classmethod
    def check_is_first_business_day_of_month(cls, reference_date):
        """
        Checks if the provided date is the first business day of month.
        A business day is any day that is not a weekend day or a local
        Brazil-SaoPaulo or international holiday.

        :param reference_date: date used as reference for the evaluation
        :type reference_date: str
        :rtype: bool
        """
        first_business_day_date = cls.get_business_days_in_month(reference_date)[0]
        return first_business_day_date.strftime("%Y-%m-%d") == reference_date

    @classmethod
    def check_is_second_business_day_of_month(cls, reference_date):
        """
        Checks if the provided date is the second business day of month.
        A business day is any day that is not a weekend day or a local
        Brazil-SaoPaulo or international holiday.

        :param reference_date: date used as reference for the evaluation
        :type reference_date: str
        :rtype: bool
        """
        second_business_day_date = cls.get_business_days_in_month(reference_date)[1]
        return second_business_day_date.strftime("%Y-%m-%d") == reference_date

    @classmethod
    def check_is_last_business_day_of_month(cls, reference_date):
        """
        Checks if the provided date is the last business day of month.
        A business day is any day that is not a weekend day or a local
        Brazil-SaoPaulo or international holiday.

        :param reference_date: date used as reference for the evaluation
        :type reference_date: str
        :rtype: bool
        """
        last_business_day_date = cls.get_business_days_in_month(reference_date)[-1]
        return last_business_day_date.strftime("%Y-%m-%d") == reference_date

    @staticmethod
    def check_is_specific_day_of_month(reference_date, day: int):
        """
        Checks if the provided date is in the provided day of month.

        :param reference_date: date used as reference for the evaluation
        :type reference_date: str
        :param weekday: integer of the day of the month, from 1 to 31.
        :type weekday: int
        :rtype: bool
        """
        return datetime.strptime(reference_date, "%Y-%m-%d").day == day

    @staticmethod
    def check_is_specific_weekday(reference_date, weekday: int):
        """
        Checks if the provided date is of the provided week day.

        :param reference_date: date used as reference for the evaluation
        :type reference_date: str
        :param weekday: integer representing the week day to be evaluated,
            starting on Monday as 0 and ending on Sunday as 6.
        :type weekday: int
        :rtype: bool
        """
        return datetime.strptime(reference_date, "%Y-%m-%d").weekday() == weekday

    @staticmethod
    def check_is_in_range_of_weekdays(reference_date, weekday_list: list):
        """
        Checks if the provided date is in the provided week day list.

        :param reference_date: date used as reference for the evaluation
        :type reference_date: str
        :param weekday: list of integers representing the week day to be evaluated,
            starting on Monday as 0 and ending on Sunday as 6.
        :type weekday: list[int]
        :rtype: bool
        """
        return datetime.strptime(reference_date, "%Y-%m-%d").weekday() in weekday_list

    @staticmethod
    def check_is_in_range_of_days(reference_date, range_of_days: list):
        """
        Checks if the provided date is in the provided range of days.

        :param reference_date: date used as reference for the evaluation
        :type reference_date: str
        :param range_of_days: a list of date strings in the format 'YYYY-DD-MM',
            from which the reference date will be evaluated.
        :type range_of_days: list[str]
        :rtype: bool
        """
        return datetime.strptime(reference_date, "%Y-%m-%d").day in range_of_days
