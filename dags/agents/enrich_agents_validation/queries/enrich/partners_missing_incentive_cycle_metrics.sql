WITH member_profiles_bc AS (
    SELECT DISTINCT
        mp.id_user,
        bu.id AS id_business_unit,
        bu.hub_name,
        bu.business_context
    FROM
        datalake_hub_services_clean.member_profile AS mp
    INNER JOIN
        datalake_hub_services_clean.business_unit AS bu
            ON bu.id = mp.id_business_unit
    WHERE
        bu.operational_context IN ('TEAM_MANAGEMENT', 'ACCREDITATION_AND_TEAM_MANAGEMENT')
        AND mp.is_active = TRUE
        AND mp.profile = 'AGENT'
),
member_profiles_all AS (
    SELECT
        mp.id_user,
        bu.business_context,
        COUNT(mp.id) AS count_mp_all
    FROM
        datalake_hub_services_clean.member_profile AS mp
    INNER JOIN
        datalake_hub_services_clean.business_unit AS bu
            ON bu.id = mp.id_business_unit
    WHERE
        bu.operational_context IN ('TEAM_MANAGEMENT', 'ACCREDITATION_AND_TEAM_MANAGEMENT')
        AND mp.is_active = TRUE
        AND mp.profile = 'AGENT'
    GROUP BY
        mp.id_user,
        bu.business_context
),
partner_metrics AS (
    SELECT
        pm.id_partner_external,
        COUNT(pm.id) AS total
    FROM
        datalake_big_agent_clean.partner_metric AS pm
    INNER JOIN
        datalake_big_agent_clean.metric_period AS mp
            ON mp.id = pm.id_metric_period
    WHERE
        pm.status = 'ACTIVE'
        AND ADD_MONTHS(CURRENT_DATE(), -2) BETWEEN mp.dt_initiated AND mp.dt_ended
        AND mp.id IN (72, 73, 74, 75, 76)
    GROUP BY
        pm.id_partner_external
),
agents_inactivated_6m AS (
    SELECT DISTINCT
        ael.id_agent
    FROM
        datalake_ebdb_clean.agent_event_log AS ael
    WHERE
        ael.event_type = 'AGENT_INACTIVATED'
        AND ael.ts_occurred < ADD_MONTHS(CURRENT_TIMESTAMP(), -6)
        AND ael.ts_occurred = (
            SELECT MAX(ael2.ts_occurred)
            FROM datalake_ebdb_clean.agent_event_log AS ael2
            WHERE ael2.id_agent = ael.id_agent
        )
)
SELECT DISTINCT
    u.id AS id_user,
    u.uuid_person,
    cap.business_context
FROM
    datalake_ebdb_clean.user AS u
INNER JOIN
    datalake_agent_accreditation.agent AS ag
        ON CAST(ag.id_user AS BIGINT) = CAST(u.id AS BIGINT)
INNER JOIN
    datalake_agent_accreditation.agent_capability AS cap
        ON cap.id_agent = ag.id_agent
LEFT JOIN
    datalake_hub_services_clean.users AS hub_u
        ON hub_u.id_external = u.id
LEFT JOIN
    member_profiles_bc AS mp_bc
        ON mp_bc.id_user = hub_u.id
        AND mp_bc.business_context = cap.business_context
LEFT JOIN
    member_profiles_all AS mp_all
        ON mp_all.id_user = hub_u.id
        AND mp_all.business_context = cap.business_context
LEFT JOIN
    datalake_big_agent_clean.incentive_engine AS ie
        ON ie.id_external_condition = CAST(mp_bc.id_business_unit AS STRING)
        AND ie.external_condition_type = 'HUB'
        AND FROM_UTC_TIMESTAMP(CURRENT_TIMESTAMP(), 'America/Sao_Paulo') >= ie.ts_validity_started
        AND (
            FROM_UTC_TIMESTAMP(CURRENT_TIMESTAMP(), 'America/Sao_Paulo') <= ie.ts_validity_ended
            OR ie.ts_validity_ended IS NULL
        )
LEFT JOIN
    partner_metrics AS pm
        ON pm.id_partner_external = u.uuid_person
LEFT JOIN
    agents_inactivated_6m AS ai6m
        ON ai6m.id_agent = ag.id_agent
INNER JOIN
    datalake_company_clean.member_profile AS cmp_mp
        ON cmp_mp.uuid_person = u.uuid_person
        AND cmp_mp.status = 'ACTIVE'
INNER JOIN
    datalake_company_clean.profile AS p
        ON p.id = cmp_mp.id_profile
INNER JOIN
    datalake_company_clean.product AS pd
        ON pd.id = cmp_mp.id_product
        AND pd.business_segment = 'AUTONOMOUS_BROKERAGE_AGENT'
LEFT JOIN
    datalake_big_agent_clean.partner_tier AS pt
        ON pt.id_partner_external = u.uuid_person
        AND FROM_UTC_TIMESTAMP(CURRENT_TIMESTAMP(), 'America/Sao_Paulo') BETWEEN pt.dt_validity_started AND pt.dt_validity_ended
        AND (
            (cap.business_context = 'RENT' AND pt.incentive_system = 'DEMAND_CONVERSION_FR')
            OR (cap.business_context = 'SALE' AND pt.incentive_system = 'DEMAND_CONVERSION_FS')
        )
WHERE
    ag.status = 'ACTIVE'
    AND cap.status = 'ENABLED'
    AND cap.type = 'DEMAND_VISIT_MANAGEMENT'
    AND u.id_country = 1
    AND pt.id IS NULL
    AND ai6m.id_agent IS NULL
    AND (
        pm.id_partner_external IS NULL
        OR pm.total < 5
    )
UNION ALL
SELECT
    -1 AS id_user,
    NULL AS uuid_person,
    NULL AS business_context
