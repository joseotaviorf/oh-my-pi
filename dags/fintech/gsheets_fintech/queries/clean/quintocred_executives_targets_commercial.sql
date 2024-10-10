SELECT
    NULLIF(executive, '') AS executive,
    CAST(NULLIF(brokers_wes, '') AS FLOAT) AS brokers_wes,
    CAST(NULLIF(target_contatos, '') AS FLOAT) AS target_contatos,
    CAST(NULLIF(target_evaluation_started, '') AS FLOAT) AS target_evaluation_started,
    CAST(NULLIF(target_credit_approved, '') AS FLOAT) AS target_credit_approved,
    CAST(NULLIF(target_new_contract, '') AS FLOAT) AS target_new_contract,
    NULLIF(month_trunc, '') AS month_trunc,
    NULLIF(month, '') AS month,
    NULLIF(year, '') AS year
FROM
    datalake_gsheets_raw.executives_targets_commercial
