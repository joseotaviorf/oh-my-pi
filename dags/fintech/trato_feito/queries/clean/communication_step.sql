SELECT
    CAST(id AS BIGINT) AS id_communication_step,
    CAST(sequence_id AS BIGINT) AS id_sequence,
    internal_comms_id AS id_internal_comms,
    day_offset,
    version,
    minimum_start_hour_utc,
    created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_trato_feito_raw.communication_step
