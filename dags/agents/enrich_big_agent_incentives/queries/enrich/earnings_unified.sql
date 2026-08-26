WITH contract_updated AS (
    SELECT DISTINCT
        id AS id_contract
    FROM
        datalake_ebdb_clean.contract
    WHERE
        ts_signed IS NOT NULL
        AND DATE(ts_created) < DATE('2026-08-01')
        AND DATE(ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
num_person_by_contract AS (
    SELECT
        c.id as id_contract,
        count(distinct u.uuid_person) AS num_person_envolved
    FROM
        contract_updated AS cu
    JOIN
        datalake_ebdb_clean.contract AS c
            ON c.id = cu.id_contract
    JOIN
        datalake_ebdb_clean.rent_flow AS rf
            ON rf.id_current_contract = c.id
    JOIN
        datalake_ebdb_clean.agent_rent_flow AS arf
            ON arf.id_rent_flow = rf.id
    JOIN
        datalake_ebdb_clean.user AS u
            ON u.id_agent = arf.id_agent
    GROUP BY 1
),
old_demand_conversion_fr AS (
    SELECT
        MD5(CONCAT(arf.id_rent_flow, arf.id_agent, 'DEMAND_CONVERSION_FR')) AS id_earning_unified,
        c.id AS id_contract,
        u.uuid_person,
        'DEMAND_CONVERSION_FR' AS incentive_system,
        '1P' AS business_model,
        'RENT' AS business_context,
        CAST(NULL AS STRING) AS participant_role,
        CAST(NULL AS STRING) AS tier_name,
        'AGENT' AS revenue_receiver_type,
        'AGENT_RENT_FLOW' AS revenue_source,
        'DEMAND' AS revenue_role,
        IF(npbc.num_person_envolved > 1, 'FIFTY', 'TIER') AS revenue_share_type,
        c.agent_brokerage_share AS revenue_share_value,
        c.agent_brokerage_share AS brokerage_fee,
        c.rent AS brokerage_amount,
        IF(npbc.num_person_envolved > 1, c.agent_brokerage_share/npbc.num_person_envolved, c.agent_brokerage_share) AS revenue_percentage,
        brokerage_amount*revenue_percentage AS revenue_amount,
        CAST(NULL AS DOUBLE) AS administration_percentage,
        CAST(NULL AS BOOLEAN) AS is_3p_lead_gen_offer,
        IF(npbc.num_person_envolved > 1, TRUE, FALSE) AS is_fifty_revenue_share,
        FALSE AS is_crcc_revenue_share,
        IF(npbc.num_person_envolved = 1, TRUE, FALSE) AS is_tier_revenue_share,
        TRUE AS is_calculated,
        c.ts_signed AS ts_created
    FROM
        contract_updated AS cu
    JOIN
        datalake_ebdb_clean.contract AS c
            ON c.id = cu.id_contract
    JOIN
        datalake_ebdb_clean.rent_flow AS rf
            ON rf.id_current_contract = c.id
    JOIN
        datalake_ebdb_clean.agent_rent_flow AS arf
            ON arf.id_rent_flow = rf.id
    JOIN
        datalake_ebdb_clean.user AS u
            ON u.id_agent = arf.id_agent
    JOIN
        num_person_by_contract AS npbc
            ON npbc.id_contract = c.id
),
old_supply_acquisition_fr AS (
    SELECT
        MD5(CONCAT(cpd.id, cpd.id_contract, pa.id, 'SUPPLY_ACQUISITION_FR')) AS id_earning_unified,
        cpd.id_contract AS id_contract,
        u.uuid_person,
        'SUPPLY_ACQUISITION_FR' AS incentive_system,
        '1P' AS business_model,
        'RENT' AS business_context,
        NULL AS participant_role,
        NULL AS tier_name,
        CASE
            WHEN cpd.partner_type = 'AUTONOMOUS_AGENT' THEN 'AGENT'
            WHEN cpd.partner_type = 'PRIME' THEN 'B2B'
            WHEN cpd.partner_type = 'EXECUTIVE_FOR_RENT' THEN 'EXECUTIVE'
            ELSE NULL
        END AS revenue_receiver_type,
        'CONTRACT_PARTNERSHIP_DATA' AS revenue_source,
        'SUPPLY' AS revenue_role,
        CASE
            WHEN cpd.partner_type = 'AUTONOMOUS_AGENT' THEN NULL
            ELSE cpd.partner_type
        END AS revenue_share_type,
        c.agent_brokerage_share AS revenue_share_value,
        c.agent_brokerage_share AS brokerage_fee,
        c.rent AS brokerage_amount,
        cpd.brokerage_split_percentage AS revenue_percentage,
        brokerage_amount*revenue_percentage AS revenue_amount,
        cpd.administration_split_percentage AS administration_percentage,
        FALSE AS is_3p_lead_gen_offer,
        NULL AS is_fifty_revenue_share,
        NULL AS is_crcc_revenue_share,
        NULL AS is_tier_revenue_share,
        ROW_NUMBER() OVER(PARTITION BY cpd.id_contract, cpd.partner_type ORDER BY cpd.id DESC) = 1 AS is_calculated,
        cpd.ts_created
    FROM
        contract_updated AS cu
    JOIN
        datalake_ebdb_clean.contract AS c
            ON c.id = cu.id_contract
    JOIN
        datalake_ebdb_clean.contract_partnership_data AS cpd
            ON cpd.id_contract = c.id
    JOIN
        datalake_ebdb_clean.partner AS p
            ON p.id = cpd.id_partner
    JOIN
        datalake_ebdb_clean.partner_agent AS pa
            ON pa.id_partner = p.id
    JOIN
        datalake_ebdb_clean.user AS u
            ON u.id = pa.id_user
),
old_fr AS (
    SELECT
        id_earning_unified,
        id_contract,
        uuid_person,
        revenue_receiver_type,
        incentive_system,
        business_model,
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
        administration_percentage,
        is_3p_lead_gen_offer,
        is_fifty_revenue_share,
        is_crcc_revenue_share,
        is_tier_revenue_share,
        is_calculated,
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
        business_model,
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
        administration_percentage,
        is_3p_lead_gen_offer,
        is_fifty_revenue_share,
        is_crcc_revenue_share,
        is_tier_revenue_share,
        is_calculated,
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
        '1P' AS business_model,
        e.business_context,
        CAST(NULL AS STRING) AS participant_role,
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
        CAST(NULL AS DOUBLE) AS administration_percentage,
        e.is_3p_lead_gen_offer,
        e.is_fifty_revenue_share,
        e.is_crcc_revenue_share,
        e.is_tier_revenue_share,
        e.is_calculated,
        e.ts_created
    FROM
        datalake_big_agent.earnings AS e
    LEFT JOIN
        datalake_ebdb_clean.contract AS c
            ON e.id_contract = c.id
    WHERE
        DATE(c.ts_created) >= DATE('2026-08-01')
        AND DATE(e.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    id_earning_unified,
    id_contract,
    uuid_person,
    revenue_receiver_type,
    incentive_system,
    business_model,
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
    administration_percentage,
    is_3p_lead_gen_offer,
    is_fifty_revenue_share,
    is_crcc_revenue_share,
    is_tier_revenue_share,
    is_calculated,
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
    business_model,
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
    administration_percentage,
    is_3p_lead_gen_offer,
    is_fifty_revenue_share,
    is_crcc_revenue_share,
    is_tier_revenue_share,
    is_calculated,
    ts_created,
    YEAR(ts_created) AS year,
    MONTH(ts_created) AS month,
    DAY(ts_created) AS day
FROM
    new_earnings
