SELECT
    CAST(id AS BIGINT) AS id_segment,
    name,
    description,
    version,
    CAST(priority AS INT) AS priority,
    active AS is_active,
    created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_trato_feito_raw.segment
