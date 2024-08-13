SELECT
    id AS id_airtable_record,
    CAST(id_partner AS BIGINT) AS id_partner,
    Categoria AS category,
    Carteira AS wallet,
    TO_DATE(start_date,'yyyy-MM-dd') AS dt_started,
    TO_DATE(end_date, 'yyyy-MM-dd') AS dt_ended,
    TO_TIMESTAMP(last_modified) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_airtable_test_raw.wallet
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}