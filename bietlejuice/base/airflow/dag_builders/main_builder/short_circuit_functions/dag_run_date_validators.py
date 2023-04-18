from datetime import datetime


class DAGRunDateValidators:
    def __init__(
        self,
        dag_execution_date: str,
        start_interval: str = None,
        end_interval: str = None,
    ):
        from workalendar.america import BrazilSaoPauloCity

        self.dag_execution_date = dag_execution_date
        self.start_interval = start_interval
        self.end_interval = end_interval

        self.holidays = [
            date[0].strftime("%Y-%m-%d")
            for date in BrazilSaoPauloCity(years=[datetime.now().year]).holidays()
        ]

    def business_days(self):
        import pandas as pd

        first_day_of_month = f"01-{datetime.now().month}-{datetime.now().year}"
        get_last_day_object = pd.date_range(
            f"{datetime.now().year}-{datetime.now().month}", periods=1, freq="M"
        )
        last_day_of_month = get_last_day_object[0].date()

        business_ts_in_month = [
            datetime.timestamp(date)
            for date in pd.bdate_range(first_day_of_month, last_day_of_month)
        ]
        business_date_in_month = [
            datetime.fromtimestamp(date).strftime("%Y-%m-%d")
            for date in business_ts_in_month
        ]

        return business_date_in_month

    def first_business_day_of_month(self):
        return (
            self.dag_execution_date in self.business_days()
            and self.dag_execution_date not in self.holidays
        )
