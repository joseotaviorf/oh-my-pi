import datetime
import businesstimedelta
import holidays as pyholidays


class FintechUDFs:
    @staticmethod
    def fintechops_work_min_sla(
        ts_started: datetime.datetime, ts_finished: datetime.datetime
    ) -> float:
        workday = businesstimedelta.WorkDayRule(
            start_time=datetime.time(8),
            end_time=datetime.time(20),
            working_days=[0, 1, 2, 3, 4],
        )
        workday_sat = businesstimedelta.WorkDayRule(
            start_time=datetime.time(8), end_time=datetime.time(18), working_days=[5]
        )

        my_holidays = pyholidays.country_holidays("BR", subdiv="SP")
        holidays = businesstimedelta.HolidayRule(my_holidays)

        business_hours = businesstimedelta.Rules([workday, workday_sat, holidays])

        working_hours_delta = business_hours.difference(ts_started, ts_finished)
        working_hours_delta_to_seconds = working_hours_delta.hours * 3600.0

        ts_working_hours = (
            working_hours_delta.seconds + working_hours_delta_to_seconds
        ) / 60.0
        return ts_working_hours

    @staticmethod
    def fintech_collections_renegotiation(invoice: str, invoice_map: str) -> list:
        level = 0
        while invoice in invoice_map:
            invoice = invoice_map[invoice]
            level += 1
        return invoice, level
