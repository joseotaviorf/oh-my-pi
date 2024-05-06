SELECT
    id,
    origin,
    type,
    company_group,
    created_at AS ts_created
FROM
    datalake_trato_feito_raw.debtor
