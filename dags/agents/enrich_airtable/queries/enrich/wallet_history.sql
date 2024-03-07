SELECT
    id_airtable_record,
    id_partner,
    category,
    wallet,
    dt_started,
    dt_ended,
    ts_updated,
    year,
    month,
    day
FROM
    datalake_airtable_clean.wallet_history
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_partner,category,wallet, dt_started ORDER BY ts_updated DESC) = 1