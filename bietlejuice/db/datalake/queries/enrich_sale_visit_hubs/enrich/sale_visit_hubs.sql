WITH member_profile_order AS (
    SELECT 
        *, 
        ROW_NUMBER() OVER(
                PARTITION BY id ORDER BY version DESC
        ) AS r
    FROM 
        datalake_hub_services_clean.member_profile
),
member_profile AS (
    SELECT 
        mp.id,
        mp.id_business_unit,
        mp.id_user,
        mp.id_parent_member_profile,
        mp.version,
        mp.profile,
        CASE 
            WHEN r!=1 
                THEN false 
            ELSE mp.is_active 
        END AS is_active,
        COALESCE(LAG(mp.ts_updated) OVER (PARTITION BY mp.id ORDER BY mp.version), mp.ts_created) AS ts_created,
        CASE 
            WHEN mp.r = 1 AND mp.is_active = true 
                THEN CURRENT_DATE 
            ELSE mp.ts_updated 
        END AS ts_updated,
        r
    FROM 
        member_profile_order AS mp
),
business_unit_order AS (
    SELECT 
        id, 
        MAX(version) AS version 
    FROM 
        datalake_hub_services_clean.business_unit 
    GROUP BY 1
),
business_units AS (
    SELECT
        bu.*
    FROM 
        datalake_hub_services_clean.business_unit AS bu 
    JOIN 
        business_unit_order AS buo
            ON bu.id = buo.id 
            AND bu.version = buo.version
),
users_order AS (
    SELECT 
        id, 
        MAX(version) AS version 
    FROM 
        datalake_hub_services_clean.users 
    GROUP BY 1
),
users AS (
    SELECT
        u.*
    FROM 
        datalake_hub_services_clean.users AS u
    JOIN 
        users_order AS uo
            ON u.id = uo.id 
            AND u.version = uo.version
),
teams_relations AS (
    SELECT 
        mp.id,
        mp.id_business_unit,
        bu.hub_name,
        u1.id_external AS id_user_agent,
        u2.id_external AS id_user_en,
        mp.ts_created AS ts_started,
        mp.ts_updated AS ts_ended
    FROM
        member_profile AS mp
    LEFT JOIN 
        business_units AS bu
            ON mp.id_business_unit = bu.id
    LEFT JOIN 
        users AS u1
            ON mp.id_user = u1.id
    LEFT JOIN 
        users AS u2
            ON mp.id_parent_member_profile = u2.id
    WHERE
        bu.hub_name NOT LIKE "%[For rent]%"
),

work_contract AS (
    SELECT
        aud.id_agent,
        aud.id_user_change,
        aud.work_contract_name,
        aud.ts_revision AS ts_started,
        COALESCE(LEAD(aud.ts_revision) OVER(PARTITION BY aud.id_agent ORDER BY aud.rev), CURRENT_DATE) AS ts_ended
    FROM 
        datalake_ebdb_agents.agents_activations_suspensions_contracts_changes AS aud
),
wc_hubs_padronization AS (
    SELECT
        wc.id_agent,
        wc.id_user_change AS id_user_agent,
        IF (wc.work_contract_name = bus.hub_name_wc, bus.id_business_unit_teams, NULL) AS id_hub,
        IF (wc.work_contract_name = bus.hub_name_wc, bus.hub_name_teams, NULL) AS hub_name,
        wc.ts_started,
        wc.ts_ended
    FROM 
        work_contract AS wc
    LEFT JOIN
        datalake_gsheets_clean.sale_business_unit_standardization AS bus
            ON bus.hub_name_wc = wc.work_contract_name
),
work_contract_relations AS (
    SELECT
        ua.id_agent,
        ua.id AS id_user_agent,
        wc.id_hub,
        wc.hub_name,
        wc.ts_started,
        wc.ts_ended
    FROM
        wc_hubs_padronization AS wc
    LEFT JOIN
        datalake_ebdb_user.user AS ua
            ON wc.id_agent = ua.id_agent
),

business_unit_region_relations AS (
    SELECT
        IF (bur.business_unit = bus.hub_name_bur, bus.id_business_unit_teams, NULL) AS id_hub,
        bur.id_region,
        bur.business_unit AS hub_name,
        bur.dt_start,
        bur.dt_end
    FROM 
        datalake_gsheets_clean.business_unit_region AS bur
    LEFT JOIN 
        datalake_gsheets_clean.sale_business_unit_standardization AS bus
            ON bus.hub_name_bur = bur.business_unit
),

visit_relation AS (
    SELECT
        b.id AS id_booking,
        COALESCE(tr.id_business_unit, wcr.id_hub, bur.id_hub) AS id_business_unit,
        COALESCE(tr.hub_name, wcr.hub_name, bur.hub_name) AS business_unit,
        b.id_user_sale_agent AS id_user_agent,
        tr.id_user_en,
        b.ts_created AS ts_visit_intent
    FROM
        datalake_booking.booking AS b
    LEFT JOIN
        datalake_ebdb_clean.house AS h
          ON h.id = b.id_house
    LEFT JOIN
        teams_relations AS tr
          ON tr.id_user_agent = b.id_user_sale_agent
          AND b.ts_created BETWEEN tr.ts_started AND tr.ts_ended
    LEFT JOIN 
        work_contract_relations AS wcr
          ON wcr.id_user_agent = b.id_user_sale_agent
          AND b.ts_created BETWEEN wcr.ts_started AND wcr.ts_ended
          AND wcr.id_hub IS NOT NULL
    LEFT JOIN
        business_unit_region_relations AS bur
          ON bur.id_region = h.id_region
          AND b.ts_created BETWEEN bur.dt_start AND bur.dt_end
          AND bur.id_hub IS NOT NULL
    WHERE
        b.visit_intent = 'SALE'
)

SELECT
    id_booking,
    id_business_unit,
    id_user_agent,
    id_user_en,
    business_unit,
    ts_visit_intent
FROM 
    visit_relation
