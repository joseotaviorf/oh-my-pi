WITH explode_ciq_users AS (
  SELECT
      cu.id_partner,
      cu.id_user,
      COALESCE(u.id_agent, -1) AS id_agent,
      cu.status,
      cu.email,
      cu.ts_agent_status_start,
      EXPLODE(SEQUENCE(DATE(cu.ts_agent_status_start), DATE(COALESCE(cu.ts_agent_status_end, DATE('{load_end_date}'))))) AS dt_reference
  FROM
      datalake_ebdb_agents.ciq_users AS cu
  LEFT JOIN
      datalake_ebdb_user.user AS u
        ON cu.id_user = u.id
),
ciq_daily_history AS (
  SELECT
      id_partner,
      id_user,
      id_agent,
      status,
      email,
      ROW_NUMBER() OVER (PARTITION BY id_partner, dt_reference ORDER BY ts_agent_status_start DESC) = 1 AS is_last_status_by_date,
      dt_reference
  FROM
      explode_ciq_users
),
logins_pm_per_day AS (
  SELECT
      email,
      DATE(ts_event) AS dt_event,
      COUNT(email) AS qtd_logins
  FROM
      datalake_amplitude_clean.440441_home_page_viewed_events
  WHERE
      login_status IS TRUE
      AND MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  GROUP BY 1,2
),
agent_profile_history AS (
    SELECT
        id_agent_data AS id_agent,
        profile,
        DATE(ts_revision_started) AS dt_started,
        DATE(ts_revision_ended) AS dt_ended
    FROM
        datalake_agent_accreditation.agent_profile AS ap
    WHERE
        is_lastest_by_date IS TRUE
),
accreditation_history AS (
    SELECT
        id_agent,
        action,
        ROW_NUMBER() OVER (PARTITION BY id_agent, dt_action ORDER BY ts_revision DESC) = 1 AS is_last_action_by_date,
        DATE(ts_revision) AS dt_started,
        DATE(COALESCE(LEAD(ts_revision) OVER (PARTITION BY id_agent ORDER BY ts_revision ASC) - INTERVAL '1' DAY, DATE('{load_end_date}'))) AS dt_ended
    FROM
        datalake_agent_accreditation.agent_registration_actions_log
    WHERE
        action IN ("Re-accreditation", "De-accreditation", "Accreditation")
        AND DATE(ts_revision) <= DATE('{load_end_date}')
),
agent_status_history AS (
    WITH agent_registration_actions_log AS (
        SELECT
            id_agent,
            id_user,
            id_work_contract,
            visit_agent_type,
            ROW_NUMBER() OVER (PARTITION BY id_agent, dt_action ORDER BY ts_revision DESC) = 1 AS is_last_action_by_date,
            is_active,
            ts_revision,
            dt_action AS dt_started
        FROM
            datalake_agent_accreditation.agent_registration_actions_log
        WHERE
            DATE(ts_revision) <= DATE('{load_end_date}')
    )
    SELECT 
        id_agent,
        id_user,
        id_work_contract,
        visit_agent_type,
        is_active,
        dt_started,
        COALESCE(LEAD(dt_started) OVER (PARTITION BY id_agent ORDER BY ts_revision ASC) - INTERVAL '1' DAY, DATE(NOW())) AS dt_ended
    FROM 
        agent_registration_actions_log
    WHERE
        is_last_action_by_date IS TRUE 
),
business_context AS (
    SELECT
        id_agent_data,
        business_context,
        ts_revision_started,
        COALESCE(ts_revision_ended, TIMESTAMP('{load_end_date}')) AS ts_revision_ended
    FROM
        datalake_agent_accreditation.business_context
    GROUP BY 1, 2, 3, 4 -- the same id_agent_data can have multiple rows by id_agent, so we need to group by them
)
SELECT
    cdh.id_partner,
    cdh.id_user,
    cdh.id_agent,
    COALESCE(ash.id_work_contract, -1) AS id_work_contract,
    cdh.status AS ciq_status,
    COALESCE(lpd.qtd_logins, 0) AS qty_logins,
    COALESCE(aph.profile, 'N/A') AS agent_profile,
    COALESCE(bca.business_context, 'N/A') AS business_context,
    COALESCE(ash.is_active, FALSE) AS is_agent_active,
    COALESCE(aha.action, 'N/A') AS accreditation_status,
    COALESCE(ash.visit_agent_type, 'N/A') AS visit_agent_type,
    cdh.dt_reference,
    YEAR(cdh.dt_reference) AS year,
    MONTH(cdh.dt_reference) AS month,
    DAY(cdh.dt_reference) AS day
FROM
    ciq_daily_history AS cdh
LEFT JOIN
    logins_pm_per_day AS lpd
      ON cdh.email = lpd.email
      AND cdh.dt_reference = lpd.dt_event
LEFT JOIN
    agent_profile_history AS aph
      ON cdh.id_agent = aph.id_agent
      AND cdh.dt_reference BETWEEN aph.dt_started AND COALESCE(aph.dt_ended, DATE('{load_end_date}'))
LEFT JOIN
    business_context AS bca
      ON cdh.id_agent = bca.id_agent_data
      AND cdh.dt_reference BETWEEN DATE(bca.ts_revision_started) AND DATE(bca.ts_revision_ended)
LEFT JOIN
    agent_status_history AS ash
      ON cdh.id_agent = ash.id_agent
      AND cdh.dt_reference BETWEEN ash.dt_started AND ash.dt_ended
LEFT JOIN
    accreditation_history AS aha
      ON cdh.id_agent = aha.id_agent
      AND cdh.dt_reference BETWEEN aha.dt_started AND aha.dt_ended
      AND aha.is_last_action_by_date IS TRUE
WHERE
    cdh.id_partner NOT IN (691, 674) -- Inconsistent CIQs
    AND cdh.is_last_status_by_date IS TRUE
    AND cdh.dt_reference BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
