WITH agent_accreditation AS (
    SELECT
        a.id AS id_agent,
        user.id AS id_user,
        a.id_work_contract,
        a.rev_type,
        a.creci_number,
        a.uuid_company,
        a.agent_type,
        COALESCE(  
            (
                MIN(IF(a.is_active IS TRUE, u.ts_revision, NULL)) OVER (PARTITION BY a.id ORDER BY u.ts_revision) = u.ts_revision
                AND a.is_active IS TRUE
            ),
            FALSE
        ) AS is_first_active,
        a.is_active,
        LAG(a.is_active) OVER (PARTITION BY a.id ORDER BY u.ts_revision) AS previous_is_active,
        COALESCE(
            LAG(a.is_active) OVER (PARTITION BY a.id ORDER BY u.ts_revision),
            FALSE
        ) <> a.is_active AS mod_is_active,
        COALESCE(
            LAG(a.id_work_contract) OVER (PARTITION BY a.id ORDER BY u.ts_revision),
            -1
        ) <> a.id_work_contract AS mod_id_work_contract,
        COALESCE(
            LAG(a.creci_number) OVER (PARTITION BY a.id ORDER BY u.ts_revision),
            -1
        ) <> a.creci_number AS mod_creci_number,
        COALESCE(
            LAG(a.uuid_company) OVER (PARTITION BY a.id ORDER BY u.ts_revision),
            "-1"
        ) <> a.uuid_company AS mod_uuid_company,
        COALESCE(
            LAG(a.agent_type) OVER (PARTITION BY a.id ORDER BY u.ts_revision),
            "-1"
        ) <> a.agent_type AS mod_agent_type,
        FIRST(u.ts_revision) OVER (PARTITION BY a.id ORDER BY u.ts_revision) AS ts_initial_accreditation,
        u.ts_revision,
        DATE(u.ts_revision) AS dt_revision
    FROM
        datalake_ebdb_clean.agent_data_aud AS a
    JOIN
        datalake_ebdb_clean.user 
            ON user.id_agent = a.id
    JOIN 
        datalake_ebdb_user.user_revision_entity AS u 
            ON u.id = a.rev
    WHERE
        DATE(u.ts_revision) <= DATE('{load_end_date}')
),
business_context AS (
    SELECT 
        bc.id_agent,
        bc.business_context,
        bc.ts_revision_started,
        DATE(bc.ts_revision_started) AS dt_revision_started,
        DATE(
            COALESCE(
                bc.ts_revision_ended - INTERVAL 1 DAY, 
                '{load_end_date}'
            )
        ) AS dt_revision_ended
    FROM 
        datalake_agent_accreditation.business_context AS bc
    QUALIFY
        1 = ROW_NUMBER() OVER (
            PARTITION BY bc.id_agent, DATE(bc.ts_revision_started)
            ORDER BY bc.ts_revision_started, COALESCE(bc.ts_revision_ended, DATE('{load_end_date}')) DESC
        )
),
other_actions AS (
    SELECT
        ap.id_agent,
        "Performance Profile Update" AS action,
        NULL AS business_context,
        ap.profile,
        ap.ts_revision_started,
        DATE(ap.ts_revision_started) AS dt_revision
    FROM
        datalake_agent_accreditation.agent_profile AS ap
    WHERE
        DATE(ap.ts_revision_started) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION ALL
    SELECT
        bc.id_agent,
        "Business Context Update" AS action,
        bc.business_context,
        NULL AS profile,
        bc.ts_revision_started,
        bc.dt_revision_started AS dt_revision
    FROM
        business_context AS bc
    WHERE
        bc.dt_revision_started BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
actions AS (
    SELECT /*+ RANGE_JOIN(act2, 1500) */ 
        ac.id_agent,
        ac.id_user,
        ac.id_work_contract,
        ac.creci_number,
        ac.uuid_company,
        ap.profile AS agent_profile,
        ac.agent_type AS visit_agent_type,
        bc.business_context,
        ac.is_active,
        1 = ROW_NUMBER() OVER (PARTITION BY ac.id_agent, ac.dt_revision ORDER BY ts_revision DESC) AS is_last_revision,
        CASE 
            WHEN ac.rev_type = 0 THEN "Accreditation"  
            WHEN ac.rev_type = 2 THEN "Record Removed" 
            WHEN 
                ac.rev_type = 1 
                AND ac.is_first_active IS TRUE 
                AND ac.mod_is_active IS TRUE 
                AND ac.is_active IS TRUE 
                AND ac.previous_is_active IS FALSE 
                THEN "First activation after accreditation"   
            WHEN 
                ac.rev_type = 1 
                AND ac.mod_is_active IS TRUE 
                AND ac.is_active IS FALSE 
                THEN "De-accreditation"  
            WHEN 
                ac.rev_type = 1 
                AND ac.is_first_active IS FALSE 
                AND ac.mod_is_active IS TRUE 
                AND ac.is_active IS TRUE 
                AND ac.previous_is_active IS FALSE 
                THEN "Re-accreditation"  
            WHEN 
                ac.rev_type = 1 
                AND (
                    ac.mod_id_work_contract IS TRUE 
                    OR ac.mod_agent_type IS TRUE 
                    OR ac.mod_creci_number IS TRUE 
                    OR ac.mod_uuid_company IS TRUE 
                )
                THEN "Record Updated"  
        END AS action,
        ac.ts_revision,
        ac.dt_revision,
        ac.ts_initial_accreditation
    FROM
        agent_accreditation AS ac
    LEFT JOIN
        business_context AS bc -- context interval
            ON bc.id_agent = ac.id_agent
            AND ac.dt_revision BETWEEN bc.dt_revision_started AND bc.dt_revision_ended
    LEFT JOIN
        datalake_agent_accreditation.agent_profile AS ap -- profile interval
            ON ap.id_agent = ac.id_agent
            AND ac.dt_revision BETWEEN DATE(ap.ts_revision_started) 
            AND COALESCE(
                DATE(ap.ts_revision_ended - INTERVAL 1 DAY), 
                '{load_end_date}'
            )
    WHERE
        ac.dt_revision BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
business_profile_actions AS (
    SELECT DISTINCT
        ac.id_agent,
        ac.id_user,
        ac.id_work_contract,
        ac.creci_number,
        ac.uuid_company,
        COALESCE(oa.profile, ac.agent_profile) AS agent_profile,
        ac.visit_agent_type,
        COALESCE(oa.business_context, ac.business_context) AS business_context,
        ac.is_last_revision,
        ac.is_active,
        oa.action,
        COALESCE(oa.ts_revision_started, ac.ts_revision) AS ts_revision,
        ac.dt_revision,
        ac.ts_initial_accreditation
    FROM
        actions AS ac
    JOIN
        other_actions AS oa -- action date
            ON oa.id_agent = ac.id_agent
            AND oa.dt_revision = ac.dt_revision
            AND oa.dt_revision <> DATE(ac.ts_initial_accreditation)
    WHERE
        ac.is_last_revision IS TRUE
),
union_actions AS (
    SELECT * FROM actions
    UNION ALL
    SELECT * FROM business_profile_actions
)
SELECT 
    XXHASH64(a.id_agent, a.action, a.dt_revision) AS id_action_log,
    CASE 
        WHEN a.action = "Accreditation" THEN 0
        WHEN a.action = "First activation after accreditation" THEN 1
        WHEN a.action = "De-accreditation" THEN 2
        WHEN a.action = "Re-accreditation" THEN 3
        WHEN a.action = "Business Context Update" THEN 4
        WHEN a.action = "Performance Profile Update" THEN 5
        WHEN a.action = "Record Updated" THEN 6
        WHEN a.action = "Record Removed" THEN 7     
    END AS id_action,
    a.id_agent,
    a.id_user,
    a.id_work_contract,
    a.creci_number,
    a.uuid_company,
    a.agent_profile,
    a.visit_agent_type,
    a.business_context,
    a.action,
    a.is_active,
    a.ts_revision,
    a.dt_revision AS dt_action
FROM 
    union_actions AS a
WHERE 
    a.action IS NOT NULL 
QUALIFY
    1 = ROW_NUMBER() OVER (PARTITION BY id_action_log ORDER BY a.ts_revision DESC)