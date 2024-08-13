SELECT
    city_group,
    CAST(REPLACE(avg_ticket_cs_target, ',', '') AS DOUBLE) AS target,
    TO_DATE(month, 'yyyy-MM-dd') AS dt_month_started
FROM
    datalake_gsheets_raw.contracts_signed_average_ticket_targets