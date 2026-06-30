WITH broker_map AS (
  SELECT DISTINCT
    uuid_company,
    CAST(id AS VARCHAR) AS sk_broker
  FROM datalake_company_clean.company
),
sessions_agg AS (
  SELECT
    ls.uuid_lead,
    COUNT(DISTINCT ls.uuid_lead_session)                                                   AS qt_sessions_total,
    COUNT(DISTINCT CASE
      WHEN lr.uuid_lead_resolution IS NOT NULL THEN ls.uuid_lead_session
    END)                                                                                    AS qt_sessions_resolved,
    COUNT(DISTINCT CASE
      WHEN lr.type = 'ESCALATION' THEN ls.uuid_lead_session
    END)                                                                                    AS qt_sessions_escalated,
    COUNT(DISTINCT CASE
      WHEN lr.type = 'VISIT_INTENTION' THEN ls.uuid_lead_session
    END)                                                                                    AS qt_sessions_visit_intention,
    MAX(CASE WHEN lr.ts_sent_to_crm IS NOT NULL THEN TRUE ELSE FALSE END)                  AS is_crm_sent,
    MIN(ls.ts_created)                                                                      AS ts_first_contact,
    MAX(ls.ts_updated)                                                                      AS ts_last_contact
  FROM datalake_alias_clean.lead_sessions AS ls
  LEFT JOIN datalake_alias_clean.lead_resolutions AS lr
    ON ls.uuid_lead_session = lr.uuid_lead_session
  GROUP BY ls.uuid_lead
)
SELECT
  l.uuid_lead                                     AS sk_lead,
  bm.sk_broker,
  COALESCE(sa.qt_sessions_total, 0)               AS qt_sessions_total,
  COALESCE(sa.qt_sessions_resolved, 0)            AS qt_sessions_resolved,
  COALESCE(sa.qt_sessions_escalated, 0)           AS qt_sessions_escalated,
  COALESCE(sa.qt_sessions_visit_intention, 0)     AS qt_sessions_visit_intention,
  COALESCE(sa.is_crm_sent, FALSE)                 AS is_crm_sent,
  sa.ts_first_contact,
  sa.ts_last_contact,
  DATE(sa.ts_first_contact)                       AS dt_first_contact,
  CURRENT_TIMESTAMP()                             AS ts_load,
  YEAR(sa.ts_first_contact)                       AS year,
  MONTH(sa.ts_first_contact)                      AS month,
  DAY(sa.ts_first_contact)                        AS day
FROM datalake_alias_clean.leads AS l
LEFT JOIN broker_map AS bm         ON l.uuid_company = bm.uuid_company
LEFT JOIN sessions_agg AS sa       ON l.uuid_lead = sa.uuid_lead
WHERE '{load_start_date}' <= l.ts_updated
  AND l.ts_updated < '{load_end_date}'
