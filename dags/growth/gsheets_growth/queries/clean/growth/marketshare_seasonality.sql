SELECT
    category,
    CAST(correction_factor AS FLOAT) AS correction_factor,
    CAST(week_month_number AS INTEGER) AS week_month_number
FROM
    datalake_gsheets_raw.marketshare_seasonality

    