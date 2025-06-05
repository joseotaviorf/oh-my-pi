SELECT
    CAST(id AS BIGINT) AS id_segment,
    name,
    description,
    version,
    active AS is_active,
    created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_trato_feito_raw.segment
