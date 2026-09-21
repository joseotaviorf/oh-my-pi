WITH capability_updated AS (
    SELECT
        settings.id_capability
    FROM
        datalake_ebdb_clean.demand_visit_management_capability_settings AS settings
    WHERE
        DATE(settings.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION
    SELECT
        c.id AS id_capability
    FROM
        datalake_ebdb_clean.capability AS c
    WHERE
        DATE(c.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
capability_log AS (
    SELECT
        log.id_capability,
        log.id_agent,
        log.event_type IN ('AGENT_CAPABILITY_ENABLED', 'AGENT_CAPABILITY_REENABLED') AS is_capability_active,
        ROW_NUMBER() OVER(PARTITION BY log.id_capability, DATE(log.ts_occurred) ORDER BY log.ts_occurred DESC, log.ts_cdc_transaction DESC) = 1 AS is_last_update_by_date,
        log.ts_occurred AS ts_started,
        LEAD(log.ts_occurred) OVER(PARTITION BY log.id_capability ORDER BY log.ts_occurred, log.ts_cdc_transaction) AS ts_ended
    FROM
        capability_updated AS updated
    JOIN
        datalake_ebdb_clean.agent_event_log AS log
            ON updated.id_capability = log.id_capability
    WHERE
        log.event_type IN ('AGENT_CAPABILITY_ENABLED', 'AGENT_CAPABILITY_DISABLED', 'AGENT_CAPABILITY_REENABLED')
),
capability_daily AS (
    SELECT
        log.id_capability,
        log.id_agent,
        log.is_capability_active,
        log.ts_started,
        EXPLODE(SEQUENCE(DATE(log.ts_started), DATE(COALESCE(log.ts_ended - INTERVAL 1 DAY, NOW())))) AS dt_reference
    FROM
        capability_log AS log
    WHERE
        log.is_last_update_by_date IS TRUE
),
capability_events AS (
    SELECT
        COALESCE(log.id_agent, settings.id_agent) AS id_agent,
        COALESCE(log.id_capability, settings.id_capability) AS id_capability,
        settings.id_capability_settings,
        settings.business_context,
        settings.is_passive_lead_receiver,
        log.is_capability_active,
        COALESCE(LAG(log.is_capability_active) OVER (PARTITION BY log.id_capability ORDER BY log.dt_reference) <> log.is_capability_active, TRUE) AS mod_capability,
        COALESCE(LAG(settings.ts_started) OVER (PARTITION BY log.id_capability ORDER BY log.dt_reference) <> settings.ts_started, settings.id_capability_settings IS NOT NULL) AS mod_capability_settings,
        COALESCE(GREATEST(settings.ts_started, log.ts_started), log.ts_started, settings.ts_started) AS ts_updated
    FROM
        capability_daily AS log
    LEFT JOIN
        datalake_ebdb_agent_events.capability_settings AS settings
            ON settings.id_capability = log.id_capability
            AND settings.is_last_update_by_date IS TRUE
            AND log.dt_reference BETWEEN DATE(settings.ts_started) AND DATE(COALESCE(settings.ts_ended - INTERVAL 1 DAY, NOW()))
)
SELECT
    XXHASH64(event.id_capability, event.ts_updated) AS id_event_log,
    event.id_agent,
    event.id_capability,
    event.id_capability_settings,
    c.type,
    event.business_context,
    event.is_passive_lead_receiver,
    event.is_capability_active,
    FIRST_VALUE(event.ts_updated) OVER(PARTITION BY event.id_capability ORDER BY event.ts_updated DESC) = event.ts_updated AS is_current_status,
    ROW_NUMBER() OVER(PARTITION BY event.id_capability, DATE(event.ts_updated) ORDER BY event.ts_updated DESC) = 1 AS is_last_event_by_date,
    c.ts_created,
    event.ts_updated AS ts_started,
    LEAD(event.ts_updated) OVER(PARTITION BY event.id_capability ORDER BY event.ts_updated) AS ts_ended
FROM
    capability_events AS event
JOIN
    datalake_ebdb_clean.capability AS c
        ON c.id = event.id_capability
WHERE
    event.mod_capability IS TRUE
    OR event.mod_capability_settings IS TRUE
