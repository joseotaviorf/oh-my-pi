SELECT
    id,
    code,
    name,
    enabled,
    created_at AS ts_created
FROM
    datalake_trato_feito_raw.collector
