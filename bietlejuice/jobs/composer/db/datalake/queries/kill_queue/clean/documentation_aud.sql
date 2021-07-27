SELECT
    id,
    house_id AS id_house,
    tenant_id AS id_tenant, 
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    CAST(active AS BOOLEAN) is_active,
    CAST(active_mod AS BOOLEAN) AS mod_is_active,
    CAST(expires_at_mod AS BOOLEAN) AS mod_ts_expired,
    CAST(expires_at AS TIMESTAMP) AS ts_expired,
    CAST(event_date AS TIMESTAMP) AS ts_event
FROM
    datalake_kill_queue_raw.documentation_aud