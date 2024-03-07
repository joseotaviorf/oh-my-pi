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
    datalake_airtable_clean.wallet
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_partner ORDER BY ts_updated DESC) = 1