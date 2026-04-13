SELECT
    e.id_app,
    e.id_session,
    CAST(e.id_user AS BIGINT) AS id_user,
    e.id_amplitude,
    e.id_event,
    GET_JSON_OBJECT(e.user_properties, "$.personUUID") AS uuid_person,
    e.city,
    e.os_name,
    e.event_type,
    e.platform,
    e.device_type,
    e.country,
    GET_JSON_OBJECT(e.event_properties, '$.uri') AS uri,
    GET_JSON_OBJECT(e.user_properties, "$.login_status") AS login_status,
    GET_JSON_OBJECT(e.user_properties, "$.app_type") AS app_type,
    e.user_properties,
    e.event_properties,
    e.id_app = 233592 AS is_prod_event,
    e.id_app = 233591 AS is_dev_event,
    GET_JSON_OBJECT(e.user_properties, "$.app_type") = "agents-signup" AS is_agent_signup,
    TIMESTAMP(GET_JSON_OBJECT(e.user_properties, "$.attributed_at")) AS ts_attributed,
    e.ts_event,
    e.year,
    e.month,
    e.day
FROM
    datalake_amplitude_clean.events AS e
WHERE
    MAKE_DATE(e.year, e.month, e.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND e.id_app IN (233592, 233591)
    AND e.event_type IN (
      'submit_error_screen_viewed',
      'pending_analysis_success_screen_viewed',
      'welcome_screen_viewed',
      'agent_pending_status_viewed',
      'agent_inactive_status_viewed',
      'partner_agent_active_status_viewed'
    )