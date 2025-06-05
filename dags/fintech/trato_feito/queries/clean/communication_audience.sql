SELECT
    CAST(id AS BIGINT) AS id_communication_audience,
    CAST(segment_id AS BIGINT) AS id_segment,
    CAST(communication_sequence_id AS BIGINT) AS id_communication_sequence,
    name,
    version,
    collector_audience_key,
    active AS is_active,
    distribution_percentage,
    start_date AS dt_start,
    end_date AS dt_end,
    created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_trato_feito_raw.communication_audience
