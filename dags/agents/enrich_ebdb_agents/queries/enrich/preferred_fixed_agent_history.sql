WITH pfa_aud_mod_enable_revision AS (
    SELECT
        a.id,
        a.business_context,
        a.is_enabled,
        a.rev,
        CASE
            WHEN LAG(a.is_enabled) OVER(PARTITION BY a.id ORDER BY a.rev) IS NULL THEN TRUE
            WHEN a.is_enabled != LAG(a.is_enabled) OVER(PARTITION BY a.id ORDER BY a.rev) THEN TRUE
            ELSE FALSE
        END AS mod_enabled_v2,
        TIMESTAMP(FROM_UNIXTIME(r.ts_revision/1000)) AS ts_revision
    FROM
        datalake_ebdb_clean.preferred_fixed_agent_aud AS a
    LEFT JOIN
        datalake_ebdb_clean.user_revision_entity AS r
            ON r.id = a.rev
    WHERE
        (rev_type = 0
        OR rev_type = 1)
        AND r.ts_revision IS NOT NULL
),
pfa_aud_revised AS (
    SELECT
        id,
        rev,
        business_context,
        is_enabled,
        ts_revision AS ts_status_started,
        FIRST_VALUE(ts_revision) OVER(PARTITION BY id ORDER BY rev) AS ts_relation_created
    FROM
        pfa_aud_mod_enable_revision
    WHERE
        mod_enabled_v2 = TRUE
    ORDER BY id
),
pfa_instant_disable AS (
    SELECT
        id
    FROM
        pfa_aud_revised
    WHERE
        is_enabled = FALSE
        AND ts_status_started = ts_relation_created
),
pfa_aud AS (
    SELECT
        pfa.id,
        pfa.rev,
        pfa.business_context,
        pfa.is_enabled,
        pfa.ts_relation_created,
        pfa.ts_status_started,
        LEAD(pfa.ts_status_started) OVER(PARTITION BY pfa.id ORDER BY pfa.rev) AS ts_status_ended
    FROM
        pfa_aud_revised AS pfa
    LEFT JOIN
        pfa_instant_disable
            ON pfa.id = pfa_instant_disable.id
    WHERE
        pfa_instant_disable.id IS NULL
),
pfa AS (
    SELECT
        pfa_aud.id,
        pfa.id_user_visit_preferences,
        COALESCE(r.id_city, pfa.id_region) AS id_region,
        uvp.id_user AS id_visitor,
        pfa.id_agent_data AS id_agent,
        ad.id AS id_user_agent,
        pfa_aud.business_context,
        pfa.origin,
        pfa_aud.is_enabled,
        pfa_aud.ts_relation_created,
        pfa_aud.ts_status_started,
        pfa_aud.ts_status_ended
    FROM
        pfa_aud
    INNER JOIN
        datalake_ebdb_clean.preferred_fixed_agent AS pfa
            ON pfa.id = pfa_aud.id
    LEFT JOIN
        datalake_ebdb_clean.user_visit_preferences AS uvp
            ON pfa.id_user_visit_preferences = uvp.id
    LEFT JOIN
        datalake_ebdb_user.user AS ad
            ON pfa.id_agent_data = ad.id_agent
    LEFT JOIN
        datalake_region.region AS r
            ON pfa.id_region = r.id
),
simultaneous_activation_relations_identification AS (
    SELECT
        id,
        XXHASH64(id_user_visit_preferences, id_region, business_context, ts_status_started) AS id_simultaneous_relation,
        id_user_visit_preferences,
        id_region,
        business_context,
        is_enabled,
        ts_relation_created,
        ts_status_started,
        ts_status_ended
    FROM
        pfa
    WHERE
        is_enabled = TRUE
),
simultaneous_activation_relations AS (
    SELECT
        id_simultaneous_relation
    FROM
        simultaneous_activation_relations_identification
    GROUP BY 1
    HAVING
        COUNT(DISTINCT id) > 1
),
simultaneous_activation_id_relations AS (
    SELECT DISTINCT
        a.id
    FROM
        simultaneous_activation_relations_identification AS a
    LEFT JOIN
        simultaneous_activation_relations AS b
            ON a.id_simultaneous_relation = b.id_simultaneous_relation
    WHERE
        b.id_simultaneous_relation IS NOT NULL
),
pfa_enabled_relations_history AS (
    SELECT
        pfa.id,
        XXHASH64(pfa.id_user_visit_preferences, pfa.id_region, pfa.business_context) AS id_paralel_relations,
        pfa.id_user_visit_preferences,
        pfa.id_region,
        pfa.id_visitor,
        pfa.id_agent,
        pfa.id_user_agent,
        pfa.business_context,
        pfa.origin,
        pfa.is_enabled,
        pfa.ts_relation_created,
        pfa.ts_status_started,
        pfa.ts_status_ended
    FROM
        pfa
    LEFT JOIN
        simultaneous_activation_id_relations AS said
            ON pfa.id = said.id
    WHERE
        said.id IS NULL
        AND pfa.is_enabled = TRUE
),
paralel_relations_status_fix AS (
    SELECT
        id,
        CASE
            WHEN ts_status_started < LAG(ts_status_ended) OVER(PARTITION BY id_paralel_relations ORDER BY ts_status_started, id) THEN ts_status_started + INTERVAL '1' SECOND
            ELSE ts_status_started
        END AS ts_status_started_revised,
        CASE
            WHEN LEAD(ts_status_started) OVER(PARTITION BY id_paralel_relations ORDER BY ts_status_started, id) < COALESCE(ts_status_ended, NOW()) THEN LEAD(ts_status_started) OVER(PARTITION BY id_paralel_relations ORDER BY ts_status_started, id) - INTERVAL '1' SECOND
            ELSE ts_status_ended
        END AS ts_status_ended_revised
    FROM
        pfa_enabled_relations_history
    QUALIFY
        ts_status_started < LAG(ts_status_ended) OVER(PARTITION BY id_paralel_relations ORDER BY ts_status_started, id)
        OR LEAD(ts_status_started) OVER(PARTITION BY id_paralel_relations ORDER BY ts_status_started, id) < COALESCE(ts_status_ended, NOW())
)
SELECT
    XXHASH64(pfa.id, pfa.id_user_visit_preferences, pfa.id_region, pfa.business_context, COALESCE(prf.ts_status_started_revised, pfa.ts_status_started)) AS id_snapshot,
    pfa.id,
    pfa.id_user_visit_preferences,
    pfa.id_region,
    pfa.id_visitor,
    pfa.id_agent,
    pfa.id_user_agent,
    pfa.business_context,
    pfa.origin,
    pfa.is_enabled,
    pfa.ts_relation_created,
    COALESCE(prf.ts_status_started_revised, pfa.ts_status_started) AS ts_status_started,
    COALESCE(prf.ts_status_ended_revised, pfa.ts_status_ended) AS ts_status_ended
FROM
    pfa_enabled_relations_history AS pfa
LEFT JOIN
    paralel_relations_status_fix AS prf
        ON prf.id = pfa.id
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_snapshot ORDER BY COALESCE(prf.ts_status_started_revised, pfa.ts_status_started), COALESCE(prf.ts_status_ended_revised, pfa.ts_status_ended, NOW()) DESC) = 1
