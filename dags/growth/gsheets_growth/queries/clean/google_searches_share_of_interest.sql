SELECT
    brand,
    city,
    CAST(queries AS DOUBLE) AS queries,
    CAST(yearmonth AS INT) AS year_month,
    CAST(month_start AS DATE) AS month_start
FROM
    datalake_gsheets_raw.google_searches_share_of_interest
