-- Visit milestones from enrich datalake_visit.visit_schedules (visit_agent = id_user_agent).
-- Params: {event_ts_expr}, {scan_predicate}
-- Identity: sk_user = id_user_agent; id_agent from datalake_agent_accreditation.agent.
SELECT
    CAST(acc.id_user AS BIGINT) AS sk_user,
    CAST(acc.id_agent AS BIGINT) AS id_agent,
    {event_ts_expr} AS ts_event,
    CAST(vs.id_schedule AS BIGINT) AS sk_entity,
    'datalake_visit.visit_schedules.id_schedule' AS entity_type
FROM
    datalake_visit.visit_schedules AS vs
INNER JOIN
    datalake_agent_accreditation.agent AS acc
        ON CAST(vs.id_user_agent AS STRING) = CAST(acc.id_user AS STRING)
WHERE
    vs.id_user_agent IS NOT NULL
    AND acc.id_agent IS NOT NULL
    AND {event_ts_expr} IS NOT NULL
    AND ({scan_predicate})
