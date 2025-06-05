SELECT
    CAST(id AS BIGINT) AS id_communication_sequence,
    version,
    name,
    description,
    created_at AS ts_updated,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_trato_feito_raw.communication_sequence
