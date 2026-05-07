SELECT
    asue.uuid_person,
    "SIGNUP_PROFILE_CONFLICT" AS step_name,
    "BLOCKED" AS step_status,
    CASE
        WHEN asue.event_type = "partner_agent_active_status_viewed" THEN "ACTIVE_AGENT_EXISTS"
        WHEN asue.event_type = "agent_inactive_status_viewed" THEN "INACTIVE_AGENT_EXISTS"
        WHEN asue.event_type = "agent_pending_status_viewed" THEN "PROSPECT_AGENT_PENDING_APPROVAL"
    END AS status_reason,
    asue.ts_event AS ts_created
FROM
    datalake_amplitude_agents_app.agents_sign_up_events AS asue
WHERE
    MAKE_DATE(asue.year, asue.month, asue.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND asue.uuid_person IS NOT NULL
    AND asue.is_prod_event = TRUE
    AND asue.event_type IN (
        "partner_agent_active_status_viewed",
        "agent_inactive_status_viewed",
        "agent_pending_status_viewed"
    )