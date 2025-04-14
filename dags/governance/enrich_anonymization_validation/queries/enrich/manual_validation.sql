SELECT
    id_entity,
    manual_eval,
    ts_ingested,
    YEAR(ts_ingested) AS year,
    MONTH(ts_ingested) AS month,
    DAY(ts_ingested) AS day
FROM
    datalake_gsheets_clean.anonymization_manual_validation
