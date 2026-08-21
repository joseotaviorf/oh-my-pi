WITH num_person_by_contract AS (
    SELECT
        c.id as id_contract,
        count(distinct u.uuid_person) AS num_person_envolved
    FROM
        datalake_ebdb_clean.agent_rent_flow AS arf
    JOIN
        datalake_ebdb_clean.rent_flow AS rf
            ON rf.id = arf.id_rent_flow
    JOIN
        datalake_ebdb_clean.contract AS c
            ON c.id = rf.id_current_contract
    JOIN
        datalake_ebdb_clean.user AS u
            ON u.id_agent = arf.id_agent
    WHERE
        c.ts_signed IS NOT NULL
        AND DATE(c.ts_created) < DATE('2026-08-01')
        AND DATE(c.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    GROUP BY 1
),
old_demand_conversion_fr AS (
    SELECT
        MD5(CONCAT(arf.id_rent_flow, arf.id_agent, 'DEMAND_CONVERSION_FR')) AS id_earning_unified,
        c.id AS id_contract,
        u.uuid_person,
        'DEMAND_CONVERSION_FR' AS incentive_system,
        'RENT' AS business_context,
        NULL AS participant_role,
        NULL AS tier_name,
        'AGENT' AS revenue_receiver_type,
        'AGENT_RENT_FLOW' AS revenue_source,
        'DEMAND' AS revenue_role,
        IF(npbc.num_person_envolved > 1, 'FIFTY', 'TIER') AS revenue_share_type,
        c.agent_brokerage_share AS revenue_share_value,
        c.agent_brokerage_share AS brokerage_fee,
        c.rent AS brokerage_amount,
        IF(npbc.num_person_envolved > 1, c.agent_brokerage_share/npbc.num_person_envolved, c.agent_brokerage_share) AS revenue_percentage,
        brokerage_amount*revenue_percentage AS revenue_amount,
        NULL AS is_3p_lead_gen_offer,
        IF(npbc.num_person_envolved > 1, TRUE, FALSE) AS is_fifty_revenue_share,
        FALSE AS is_crcc_revenue_share,
        IF(npbc.num_person_envolved = 1, TRUE, FALSE) AS is_tier_revenue_share,
        c.ts_signed AS ts_created
    FROM
        datalake_ebdb_clean.agent_rent_flow AS arf
    JOIN
        datalake_ebdb_clean.rent_flow AS rf
            ON rf.id = arf.id_rent_flow
    JOIN
        datalake_ebdb_clean.contract AS c
            ON c.id = rf.id_current_contract
    JOIN
        datalake_ebdb_clean.user AS u
            ON u.id_agent = arf.id_agent
    JOIN
        num_person_by_contract AS npbc
            ON npbc.id_contract = c.id
    WHERE
        c.ts_signed IS NOT NULL
        AND DATE(c.ts_created) < DATE('2026-08-01')
        AND DATE(c.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
old_supply_acquisition_fr AS (
    SELECT
        MD5(CONCAT(cpd.id_contract, pa.id, 'SUPPLY_ACQUISITION_FR')) AS id_earning_unified,
        cpd.id_contract AS id_contract,
        u.uuid_person,
        'SUPPLY_ACQUISITION_FR' AS incentive_system,
        'RENT' AS business_context,
        'PRO_ACQUIRER' AS participant_role,
        NULL AS tier_name,
        'AGENT' AS revenue_receiver_type,
        'CONTRACT_PARTNERSHIP_DATA' AS revenue_source,
        'SUPPLY' AS revenue_role,
        NULL AS revenue_share_type,
        c.agent_brokerage_share AS revenue_share_value,
        c.agent_brokerage_share AS brokerage_fee,
        c.rent AS brokerage_amount,
        cpd.brokerage_split_percentage AS revenue_percentage,
        brokerage_amount*revenue_percentage AS revenue_amount,
        NULL AS is_3p_lead_gen_offer,
        NULL AS is_fifty_revenue_share,
        FALSE AS is_crcc_revenue_share,
        NULL AS is_tier_revenue_share,
        c.ts_signed AS ts_created
    FROM
        datalake_ebdb_clean.contract_partnership_data AS cpd
    JOIN
        datalake_ebdb_clean.partner AS p
            ON p.id = cpd.id_partner
    JOIN
        datalake_ebdb_clean.partner_agent AS pa
            ON pa.id_partner = p.id
    JOIN
        datalake_ebdb_clean.user AS u
            ON u.id = pa.id_user
    JOIN
        datalake_ebdb_clean.contract AS c
            ON cpd.id_contract = c.id
    WHERE
        cpd.partner_type = 'AUTONOMOUS_AGENT'
        AND c.ts_signed IS NOT NULL
        AND DATE(c.ts_created) < DATE('2026-08-01')
        AND DATE(cpd.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
old_fr AS (
    SELECT
        id_earning_unified,
        id_contract,
        uuid_person,
        revenue_receiver_type,
        incentive_system,
        business_context,
        participant_role,
        tier_name,
        revenue_source,
        revenue_role,
        revenue_share_type,
        revenue_share_value,
        brokerage_fee,
        brokerage_amount,
        revenue_percentage,
        revenue_amount,
        is_3p_lead_gen_offer,
        is_fifty_revenue_share,
        is_crcc_revenue_share,
        is_tier_revenue_share,
        ts_created
    FROM
        old_demand_conversion_fr
    UNION ALL
    SELECT
        id_earning_unified,
        id_contract,
        uuid_person,
        revenue_receiver_type,
        incentive_system,
        business_context,
        participant_role,
        tier_name,
        revenue_source,
        revenue_role,
        revenue_share_type,
        revenue_share_value,
        brokerage_fee,
        brokerage_amount,
        revenue_percentage,
        revenue_amount,
        is_3p_lead_gen_offer,
        is_fifty_revenue_share,
        is_crcc_revenue_share,
        is_tier_revenue_share,
        ts_created
    FROM
        old_supply_acquisition_fr
),
new_earnings AS (
    SELECT
        MD5(CONCAT(e.id_earning, 'BIG_AGENT')) AS id_earning_unified,
        e.id_contract,
        e.uuid_person,
        e.external_receiver_type AS revenue_receiver_type,
        e.incentive_system,
        e.business_context,
        NULL AS participant_role,
        e.tier_name,
        'BIG_AGENT' AS revenue_source,
        CASE
            WHEN SPLIT(e.incentive_system, '_')[0] = "SUPPLY" THEN "SUPPLY"
            WHEN SPLIT(e.incentive_system, '_')[0] = "DEMAND" THEN "DEMAND"
        END AS revenue_role,
        e.revenue_share_type,
        e.revenue_share_value,
        e.brokerage_fee,
        e.calculation_base_amount AS brokerage_amount,
        e.revenue_percentage,
        e.revenue_amount,
        e.is_3p_lead_gen_offer,
        e.is_fifty_revenue_share,
        e.is_crcc_revenue_share,
        e.is_tier_revenue_share,
        e.ts_created
    FROM
        datalake_big_agent.earnings AS e
    LEFT JOIN
        datalake_ebdb_clean.contract AS c
            ON e.id_contract = c.id
    WHERE
        e.is_calculated
        AND DATE(c.ts_created) >= DATE('2026-08-01')
        AND DATE(e.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    id_earning_unified,
    id_contract,
    uuid_person,
    revenue_receiver_type,
    incentive_system,
    business_context,
    participant_role,
    tier_name,
    revenue_source,
    revenue_role,
    revenue_share_type,
    revenue_share_value,
    brokerage_fee,
    brokerage_amount,
    revenue_percentage,
    revenue_amount,
    is_3p_lead_gen_offer,
    is_fifty_revenue_share,
    is_crcc_revenue_share,
    is_tier_revenue_share,
    ts_created,
    YEAR(ts_created) AS year,
    MONTH(ts_created) AS month,
    DAY(ts_created) AS day
FROM
    old_fr
UNION ALL
SELECT
    id_earning_unified,
    id_contract,
    uuid_person,
    revenue_receiver_type,
    incentive_system,
    business_context,
    participant_role,
    tier_name,
    revenue_source,
    revenue_role,
    revenue_share_type,
    revenue_share_value,
    brokerage_fee,
    brokerage_amount,
    revenue_percentage,
    revenue_amount,
    is_3p_lead_gen_offer,
    is_fifty_revenue_share,
    is_crcc_revenue_share,
    is_tier_revenue_share,
    ts_created,
    YEAR(ts_created) AS year,
    MONTH(ts_created) AS month,
    DAY(ts_created) AS day
FROM
    new_earnings
