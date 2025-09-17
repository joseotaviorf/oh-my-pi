SELECT
    id_contract,
    country_code,
    city,
    guarantee,
    status,
    dt_termination_original,
    dt_annulment,
    dt_started,
    ts_signature,
    ts_analyst_annulment_input,
    LAST_DAY(dt_reference) AS dt_closing,
    ts_database_transaction,
    ts_cdc_transaction AS ts_snapshot,
    YEAR(LAST_DAY(dt_reference)) AS year,
    MONTH(LAST_DAY(dt_reference)) AS month,
    DAY(LAST_DAY(dt_reference)) AS day,
    NOW() AS ts_load
FROM datalake_collections_aud.contract_aud_daily
WHERE LAST_DAY(dt_reference) <= CURRENT_DATE
QUALIFY ROW_NUMBER() OVER(PARTITION BY id_contract, DATE_TRUNC('MONTH', dt_reference) ORDER BY dt_reference DESC) = 1
