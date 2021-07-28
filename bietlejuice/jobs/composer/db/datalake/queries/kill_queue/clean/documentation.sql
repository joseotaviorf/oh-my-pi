SELECT
    id,
    house_id AS id_house,
    tenant_id AS id_tenant, 
    version,
    CAST(active AS BOOLEAN) is_active,
    CAST(expires_at AS TIMESTAMP) AS ts_expired,
    CAST(event_date AS TIMESTAMP) AS ts_event,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated
FROM
    datalake_kill_queue_raw.documentation