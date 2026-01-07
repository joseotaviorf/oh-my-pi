SELECT
    CAST(id AS BIGINT) AS id_communication_step,
    CAST(sequence_id AS BIGINT) AS id_sequence,
    day_offset,
    version,
    config,
    type,
    created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_trato_feito_raw.communication_step
