SELECT
    id,
    description as holiday_category,
    summary AS holiday_name,
    status,
    DATE(start.date) AS dt_holiday_start,
    DATE(end.date) AS dt_holiday_end,
    updated AS ts_updated,
    created AS ts_created,
    year,
    month,
    day
FROM
    datalake_google_calendar_raw.brazillian_holidays
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY summary, DATE(start.date) ORDER BY year DESC, month DESC, day DESC) = 1
