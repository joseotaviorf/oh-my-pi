-- Accreditation-family events for dim_agent_milestone.
-- Params: {action} — exact action string from agent_registration_actions_log.
--         {scan_predicate} — framework watermark (1=1 on bootstrap; else ts >= max(ts_last)-lookback).
-- Identity: sk_user = id_user; id_agent from datalake_agent_accreditation.agent (no dw_*).
SELECT
    CAST(acc.id_user AS BIGINT) AS sk_user,
    CAST(acc.id_agent AS BIGINT) AS id_agent,
    aral.ts_revision AS ts_event,
    CAST(aral.id_action_log AS BIGINT) AS sk_entity,
    'datalake_agent_accreditation.agent_registration_actions_log.id_action_log' AS entity_type
FROM
    datalake_agent_accreditation.agent_registration_actions_log AS aral
INNER JOIN
    datalake_agent_accreditation.agent AS acc
        ON CAST(aral.id_user AS STRING) = CAST(acc.id_user AS STRING)
WHERE
    aral.action = '{action}'
    AND acc.id_user IS NOT NULL
    AND acc.id_agent IS NOT NULL
    AND ({scan_predicate})
