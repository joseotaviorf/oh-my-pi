WITH pfa_aud AS (
    SELECT
        pfau.id,
        LAG(pfau.is_enabled) OVER(PARTITION BY pfau.id ORDER BY pfau.rev) AS lag_is_enabled,
        ure.ts_revision AS ts_started,
        pfau.is_enabled
    FROM
        datalake_ebdb_clean.preferred_fixed_agent_aud AS pfau
    LEFT JOIN
        datalake_ebdb_user.user_revision_entity AS ure
            ON ure.id = pfau.rev
),
pfa_aud_mod_is_enabled AS (
    SELECT
        id,
        ts_started,
        is_enabled
    FROM
        pfa_aud
    WHERE
        COALESCE(lag_is_enabled::integer, -1) != COALESCE(is_enabled::integer, -1)
),
pfa_enrich AS (
    SELECT
        MD5(uvp.id_user || user.id || DATE_TRUNC('SECOND', pamie.ts_started)) AS id_pfa_history,
        uvp.id_user AS id_visitor,
        user.id AS id_user_agent,
        pfa.business_context,
        pfa.origin,
        pamie.is_enabled,
        DATE_TRUNC('SECOND', pamie.ts_started) AS ts_started
    FROM
        datalake_ebdb_clean.preferred_fixed_agent AS pfa
    LEFT JOIN
        pfa_aud_mod_is_enabled AS pamie
            ON pfa.id = pamie.id
    LEFT JOIN
        datalake_ebdb_clean.user_visit_preferences AS uvp
            ON pfa.id_user_visit_preferences = uvp.id
    LEFT JOIN
        datalake_ebdb_clean.user
            ON pfa.id_agent_data = user.id_agent
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_user_agent, id_visitor, DATE_TRUNC('SECOND', pamie.ts_started) ORDER BY pamie.ts_started DESC, pfa.ts_created DESC) = 1
)
SELECT
    id_pfa_history,
    id_visitor,
    id_user_agent,
    business_context,
    origin,
    is_enabled,
    ts_started,
    LEAD(ts_started) OVER(PARTITION BY id_visitor ORDER BY ts_started) AS ts_ended
FROM
    pfa_enrich
WHERE
    id_pfa_history IS NOT NULL
