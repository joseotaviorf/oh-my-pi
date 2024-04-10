WITH agent_department AS (
    SELECT DISTINCT
        u.email,
        FIRST(g.name) OVER (PARTITION BY u.email ORDER BY u.ts_updated DESC) AS main_department
    FROM
        datalake_zendesk_clean.users AS u
    JOIN
        datalake_zendesk_clean.groups AS g
            ON u.id_default_group = g.id_group
)
SELECT DISTINCT
    e.id_amplitude,
    e.id_app,
    e.id_device,
    e.id_event,
    e.id_session,
    e.id_schema,
    e.id_inserted,
    e.id_user,
    a.id_agent,
    e.uuid,
    e.ids_amplitude_attributed,
    e.adid,
    e.event_properties,
    e.user_properties,
    GET_JSON_OBJECT(e.user_properties, '$.country') AS country_code,
    GET_JSON_OBJECT(e.user_properties, '$.email') AS agent_email,
    a.name AS agent_name,
    a.organization AS agent_company,
    dc.department AS agent_department,
    dc.team AS department_team,
    dc.journey_step AS department_journey_step,
    dc.area AS department_area,
    dc.front_or_back AS department_front_or_back,
    e.amplitude_event_type,
    e.city,
    e.country,
    e.device_brand,
    e.device_carrier,
    e.device_family,
    e.device_manufacturer,
    e.device_model,
    e.device_type,
    e.dma,
    e.event_type,
    e.idfa,
    e.ip_address,
    e.location_lat,
    e.location_lng,
    e.os_name,
    e.os_version,
    e.platform,
    e.library,
    e.region,
    e.start_version,
    e.language,
    e.version_name,
    e.sample_rate,
    e.data AS event_data,
    e.is_attribution_event,
    e.is_paying,
    e.ts_client_event,
    e.ts_client_uploaded,
    e.ts_server_received,
    e.ts_event,
    e.ts_server_uploaded,
    e.ts_user_created,
    e.ts_processed,
    e.year,
    e.month,
    e.day
FROM
    datalake_amplitude_clean.events e
LEFT JOIN
    datalake_support_users.analysts a
        ON GET_JSON_OBJECT(e.user_properties, '$.email') = a.email
LEFT JOIN
    agent_department ad
        ON GET_JSON_OBJECT(e.user_properties, '$.email') = ad.email
LEFT JOIN
    datalake_gsheets_clean.department_control dc
        ON ad.main_department = dc.department
WHERE
    id_app = 370096
    AND year = {year}
    AND month = {month}
    AND day = {day}
