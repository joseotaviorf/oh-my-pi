SELECT
    CAST(id AS BIGINT) AS id,
    CAST(house_id AS BIGINT) AS id_house,
    CAST(tenant_id AS BIGINT) AS id_tenant, 
    CAST(version AS SMALLINT) AS version,
    CAST(active AS BOOLEAN) is_active,
    CAST(expires_at AS TIMESTAMP) AS ts_expired,
    CAST(event_date AS TIMESTAMP) AS ts_event,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_kill_queue_raw.documentation
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}