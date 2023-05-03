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
    def check_is_first_business_day_of_month(cls, dag_execution_date):
        first_business_day_date = cls.get_business_days_in_month(dag_execution_date)[0]

        return first_business_day_date.strftime("%Y-%m-%d") == dag_execution_date
