WITH ranked AS (
    SELECT
        id,
        description AS holiday_category,
        summary AS holiday_name,
        status,
        DATE(start.date) AS dt_holiday_start,
        DATE(end.date) AS dt_holiday_end,
        updated AS ts_updated,
        created AS ts_created,
        year,
        month,
        day,
        ROW_NUMBER() OVER (
            PARTITION BY summary, DATE(start.date)
            ORDER BY year DESC, month DESC, day DESC
        ) AS rn
    FROM
        datalake_google_calendar_raw.brazillian_holidays
)
SELECT
    id,
    holiday_category,
    holiday_name,
    status,
    dt_holiday_start,
    dt_holiday_end,
    ts_updated,
    ts_created,
    year,
    month,
    day
FROM
    ranked
WHERE
    rn = 1
