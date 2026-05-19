SELECT
    CAST(id AS BIGINT) AS id_communication_sequence,
    version,
    name,
    description,
    loop_end_day,
    loop_start_day,
    created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_trato_feito_raw.communication_sequence
