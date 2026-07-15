SELECT
    id,
    uuid AS uuid_negotiation,
    rev,
    revtype,
    status,
    channel,
    has_write_off,
    uuid_mod AS mod_uuid_negotiation,
    status_mod AS mod_status,
    channel_mod AS mod_channel,
    has_write_off_mod AS mod_has_write_off,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_negotiation_raw.negotiation_aud
