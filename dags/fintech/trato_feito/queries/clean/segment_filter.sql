SELECT
    CAST(id AS BIGINT) AS id_segment_filter,
    CAST(segment_id AS BIGINT) AS id_segment,
    version,
    sql_query,
    created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_trato_feito_raw.segment_filter
