-- First listing milestones from datalake_tiers.ciq_first_listing (temporary until AAREDE-503).
-- Params: {event_ts_expr}, {scan_predicate}
-- Identity: sk_user = id_user; id_agent from datalake_agent_accreditation.agent.
SELECT
    CAST(acc.id_user AS BIGINT) AS sk_user,
    CAST(acc.id_agent AS BIGINT) AS id_agent,
    {event_ts_expr} AS ts_event,
    CAST(fl.id_house AS BIGINT) AS sk_entity,
    'datalake_tiers.ciq_first_listing.id_house' AS entity_type
FROM
    datalake_tiers.ciq_first_listing AS fl
INNER JOIN
    datalake_agent_accreditation.agent AS acc
        ON CAST(fl.id_user AS STRING) = CAST(acc.id_user AS STRING)
WHERE
    fl.id_user IS NOT NULL
    AND acc.id_agent IS NOT NULL
    AND {event_ts_expr} IS NOT NULL
    AND ({scan_predicate})
