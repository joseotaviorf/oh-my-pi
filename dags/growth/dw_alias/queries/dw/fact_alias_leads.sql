WITH affected_leads AS (
    SELECT
        uuid_lead
    FROM
        datalake_alias_clean.leads
    WHERE
        ts_updated >= TIMESTAMP('{load_start_date}')
        AND ts_updated < TIMESTAMP('{load_end_date}')
    UNION
    SELECT
        uuid_lead
    FROM
        datalake_alias_clean.lead_sessions
    WHERE
        ts_updated >= TIMESTAMP('{load_start_date}')
        AND ts_updated < TIMESTAMP('{load_end_date}')
    UNION
    SELECT
        ls.uuid_lead
    FROM
        datalake_alias_clean.lead_resolutions AS lr
    INNER JOIN
        datalake_alias_clean.lead_sessions AS ls
            ON lr.uuid_lead_session = ls.uuid_lead_session
    WHERE
        lr.ts_updated >= TIMESTAMP('{load_start_date}')
        AND lr.ts_updated < TIMESTAMP('{load_end_date}')
),
sessions_agg AS (
    SELECT
        ls.uuid_lead,
        COUNT(DISTINCT ls.uuid_lead_session) AS qt_sessions_total,
        COUNT(DISTINCT CASE
            WHEN lr.uuid_lead_resolution IS NOT NULL THEN ls.uuid_lead_session
        END) AS qt_sessions_resolved,
        COUNT(DISTINCT CASE
            WHEN lr.type = 'ESCALATION' THEN ls.uuid_lead_session
        END) AS qt_sessions_escalated,
        COUNT(DISTINCT CASE
            WHEN lr.type = 'VISIT_INTENTION' THEN ls.uuid_lead_session
        END) AS qt_sessions_visit_intention,
        MAX(CASE WHEN lr.ts_sent_to_crm IS NOT NULL THEN TRUE ELSE FALSE END) AS is_crm_sent,
        MIN(ls.ts_created) AS ts_first_contact,
        MAX(ls.ts_updated) AS ts_last_contact
    FROM
        datalake_alias_clean.lead_sessions AS ls
    INNER JOIN
        affected_leads AS al
            ON ls.uuid_lead = al.uuid_lead
    LEFT JOIN
        datalake_alias_clean.lead_resolutions AS lr
            ON ls.uuid_lead_session = lr.uuid_lead_session
    GROUP BY
        ls.uuid_lead
)
SELECT
    l.uuid_lead AS sk_lead,
    COALESCE(cb.sk_broker, -1) AS sk_broker,
    COALESCE(sa.qt_sessions_total, 0) AS qt_sessions_total,
    COALESCE(sa.qt_sessions_resolved, 0) AS qt_sessions_resolved,
    COALESCE(sa.qt_sessions_escalated, 0) AS qt_sessions_escalated,
    COALESCE(sa.qt_sessions_visit_intention, 0) AS qt_sessions_visit_intention,
    COALESCE(sa.is_crm_sent, FALSE) AS is_crm_sent,
    sa.ts_first_contact,
    sa.ts_last_contact,
    DATE(sa.ts_first_contact) AS dt_first_contact,
    CURRENT_TIMESTAMP() AS ts_load,
    YEAR(sa.ts_first_contact) AS year,
    MONTH(sa.ts_first_contact) AS month,
    DAY(sa.ts_first_contact) AS day
FROM
    datalake_alias_clean.leads AS l
INNER JOIN
    affected_leads AS al
        ON l.uuid_lead = al.uuid_lead
LEFT JOIN
    core_brokers.brokers AS cb
        ON l.uuid_company = cb.uuid_company
LEFT JOIN
    sessions_agg AS sa
        ON l.uuid_lead = sa.uuid_lead
