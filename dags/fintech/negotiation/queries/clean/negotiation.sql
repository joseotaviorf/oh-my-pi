SELECT
    id,
    uuid AS uuid_negotiation,
    status,
    channel,
    has_write_off,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_negotiation_raw.negotiation
