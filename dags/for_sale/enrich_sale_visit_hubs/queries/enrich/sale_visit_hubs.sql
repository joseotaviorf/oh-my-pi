WITH member_profile_order AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS r
    FROM
        datalake_hub_services_clean.member_profile
),
member_profile_aux AS (
  SELECT
        mpo.id,
        mpo.id_business_unit,
        mpo.id_user,
        mpo.version,
        mpo.id_parent_member_profile,
        mpo.profile,
        CASE WHEN
            mpo.r!=1
                THEN false
            ELSE
                mpo.is_active
        END AS is_actual_active,
        mpo.ts_updated AS ts_started,
        CASE WHEN
            mpo.r = 1 AND mpo.is_active = true
                THEN current_date
            ELSE
                COALESCE(LEAD(mpo.ts_updated) OVER(PARTITION BY mpo.id ORDER BY mpo.ts_updated), mpo.ts_updated)
        END AS ts_ended,
        mpo.r
    FROM
        member_profile_order AS mpo
),
member_profile AS (
    SELECT
        mp_p.id_user AS id_user_parent,
        mp.*
    FROM
        member_profile_aux AS mp
    LEFT JOIN
        member_profile_aux AS mp_p
            ON mp_p.id = mp.id_parent_member_profile
            AND mp_p.r = 1
),
business_units AS (
    SELECT
        id AS id_business_unit,
        hub_name,
        business_context,
        negotiation_type,
        sdr_type,
        lead_types,
        ts_updated,
        ts_created
    FROM
        datalake_hub_services_clean.business_unit AS bu
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_business_unit ORDER BY version DESC) = 1
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
        bu.id_business_unit,
        bu.hub_name,
        u1.id_external AS id_user_agent,
        u2.id_external AS id_user_en,
        mp.ts_started,
        mp.ts_ended
    FROM
        member_profile AS mp
    LEFT JOIN
        business_units AS bu
            ON mp.id_business_unit = bu.id_business_unit
    LEFT JOIN
        users AS u1
            ON mp.id_user = u1.id
    LEFT JOIN
        users AS u2
            ON mp.id_user_parent = u2.id
    WHERE
        bu.hub_name NOT LIKE "%[For rent]%"
),

work_contract AS (
    SELECT
        ac.id_user_agent,
        ac.work_contract_name,
        ac.ts_work_contract_started AS ts_started,
        COALESCE(ac.ts_work_contract_ended, CURRENT_DATE) AS ts_ended
    FROM
        datalake_ebdb_agents.agent_contract AS ac
),
wc_hubs_padronization AS (
    SELECT
        wc.id_user_agent,
        IF (wc.work_contract_name = bus.hub_name, bus.id_business_unit, NULL) AS id_hub,
        IF (wc.work_contract_name = bus.hub_name, bus.hub_name, NULL) AS hub_name,
        wc.ts_started,
        wc.ts_ended
    FROM
        work_contract AS wc
    LEFT JOIN
        business_units AS bus
            ON bus.hub_name = wc.work_contract_name
),

business_unit_region_relations AS (
    SELECT
        bur.id_business_unit AS id_hub,
        bur.id_region,
        bur.hub_name,
        DATE(bur.ts_start_coverage) AS dt_start,
        COALESCE(DATE(bur.ts_end_coverage), CURRENT_DATE) AS dt_end
    FROM
        datalake_hub_services.business_unit_region AS bur
    WHERE 
        bur.hub_name NOT LIKE "%[For rent]%"
),

visit_relation AS (
    SELECT
        b.id AS id_booking,
        COALESCE(tr.id_business_unit, whp.id_hub, bur.id_hub) AS id_business_unit,
        COALESCE(tr.hub_name, whp.hub_name, bur.hub_name) AS business_unit,
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
        wc_hubs_padronization AS whp
          ON whp.id_user_agent = b.id_user_sale_agent
          AND b.ts_created BETWEEN whp.ts_started AND whp.ts_ended
          AND whp.id_hub IS NOT NULL
    LEFT JOIN
         business_unit_region_relations AS bur
           ON bur.id_region = h.id_region
           AND b.ts_created BETWEEN bur.dt_start AND bur.dt_end
           AND bur.id_hub IS NOT NULL
    WHERE
        b.visit_intent = 'SALE'
        AND b.id_user_sale_agent IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_booking ORDER BY tr.ts_started ASC) = 1
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
