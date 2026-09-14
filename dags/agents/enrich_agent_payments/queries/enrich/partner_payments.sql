WITH nazare_revenue_share AS (
    SELECT
        rs.id_revenue_share,
        rs.id_house,
        rs.id_offer_agent,
        rs.id_offer_partner,
        GET_JSON_OBJECT(rs.json_output, '$.earning-source-uuid') AS uuid_earning_source,
        rs.participant_role,
        TRIM(GET_JSON_OBJECT(rs.json_output, '$.offer-category')) AS offer_category,
        TRIM(GET_JSON_OBJECT(rs.json_output, '$.tier-name')) AS tier_name,
        CAST(GET_JSON_OBJECT(rs.json_output, '$.tqc-bonus') AS DOUBLE) AS tqc_bonus,
        CAST(GET_JSON_OBJECT(rs.json_output, '$.campaign-bonus') AS DOUBLE) AS campaign_bonus,
        CAST(GET_JSON_OBJECT(rs.json_output, '$.remuneration-bonus') AS DOUBLE) AS remuneration_bonus,
        CAST(GET_JSON_OBJECT(rs.json_output, '$.advance-bonus') AS DOUBLE) AS advance_bonus,
        CAST(GET_JSON_OBJECT(rs.json_output, '$.supply-acquisition-share') AS DOUBLE) AS supply_acquisition_share,
        CAST(GET_JSON_OBJECT(rs.json_output, '$.remuneration-baseline') AS DOUBLE) AS remuneration_baseline,
        COALESCE(
            CAST(GET_JSON_OBJECT(rs.json_output, '$.quintoandar-model-partner-brokerage-fee') AS DOUBLE),
            CAST(GET_JSON_OBJECT(rs.json_output, '$.forbrokers-model-partner-brokerage-fee') AS DOUBLE),
            CAST(GET_JSON_OBJECT(rs.json_output, '$.participant-paid-fee') AS DOUBLE),
            0
        ) AS final_revenue_share_percentage,
        CAST(GET_JSON_OBJECT(rs.json_output, '$.gross-remuneration') AS DOUBLE) AS gross_remuneration,
        CAST(GET_JSON_OBJECT(rs.json_output, '$.sale-price') AS DOUBLE) AS sale_price,
        CAST(GET_JSON_OBJECT(rs.json_output, '$.remuneration-baseline') AS DOUBLE) AS brokerage,
        CAST(GET_JSON_OBJECT(rs.json_output, '$.forbrokers-model-partner-brokerage-fee') AS DOUBLE) > 0 AS is_3p_partnership,
        GREATEST(rs.ts_created, rs.ts_database_transaction) AS ts_updated,
        rs.ts_created
    FROM
        datalake_nazare_clean.revenue_share_by_participant AS rs
    WHERE
        ts_invalidated IS NULL
        AND DATE(GREATEST(rs.ts_created, rs.ts_database_transaction)) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
sales_flow_offer AS (
    SELECT
        sfo.id_firestore AS id_offer,
        sfo.id_sales_flow,
        fee.brokerage_fee,
        ccv.ts_signed AS ts_contract_signed
    FROM
        datalake_sales_flow_clean.offer AS sfo
    LEFT JOIN
        datalake_sales_flow_clean.brokerage AS fee
            ON fee.id_sales_flow = sfo.id_sales_flow
    LEFT JOIN
        datalake_sales_flow_clean.ccv AS ccv
            ON ccv.id_sales_flow = sfo.id_sales_flow
),
nazare_offer_agent AS (
    SELECT
        oa.id_offer_agent,
        a.id_external AS id_user,
        o.id_external AS id_offer,
        o.id_business_unit,
        sfo.id_sales_flow,
        a.uuid_external_person AS uuid_person,
        sfo.brokerage_fee,
        sfo.ts_contract_signed
    FROM
        datalake_nazare_clean.offer_agent AS oa
    LEFT JOIN
        datalake_nazare_clean.agent AS a
            ON a.id_agent = oa.id_agent
    LEFT JOIN
        datalake_nazare_clean.offer AS o
            ON o.id_offer = oa.id_offer
    LEFT JOIN
        sales_flow_offer AS sfo
            ON sfo.id_offer = o.id_external
),
nazare_offer_partner AS (
    SELECT
        op.id_offer_partner,
        o.id_external AS id_offer,
        sfo.id_sales_flow,
        p.uuid_company,
        sfo.brokerage_fee,
        sfo.ts_contract_signed
    FROM
        datalake_nazare_clean.offer_partner AS op
    LEFT JOIN
        datalake_nazare_clean.partner AS p
            ON p.id_partner = op.id_partner
    LEFT JOIN
        datalake_nazare_clean.offer AS o
            ON o.id_offer = op.id_offer
    LEFT JOIN
        sales_flow_offer AS sfo
            ON sfo.id_offer = o.id_external
),
union_nazare_incentives AS (
    SELECT
        rs.id_revenue_share,
        "SUPPLY_ACQUISITION_FS" AS incentive_system,
        NULL AS replacement_incentive_system,
        IF(rs.is_3p_partnership IS TRUE, "COMPANY", "AGENT") AS revenue_receiver_type,
        COALESCE(
            rs.supply_acquisition_share,
            rs.final_revenue_share_percentage
        ) AS revenue_percentage,
        rs.ts_created
    FROM
        nazare_revenue_share AS rs
    WHERE
        rs.participant_role IN ('CIQ', 'SUPPLY')
    UNION
    SELECT
        rs.id_revenue_share,
        "DEMAND_ACQUISITION_FS" AS incentive_system,
        NULL AS replacement_incentive_system,
        "AGENT" AS revenue_receiver_type,
        COALESCE(rs.tqc_bonus, 0) AS revenue_percentage,
        rs.ts_created
    FROM
        nazare_revenue_share AS rs
    WHERE
        rs.participant_role NOT IN ('CIQ', 'SUPPLY')
        AND COALESCE(rs.tqc_bonus, 0) <> 0
    UNION
    SELECT
        rs.id_revenue_share,
        "DEMAND_CONVERSION_FS" AS incentive_system,
        CASE
            WHEN rs.participant_role = "EXECUTIVO_NEGOCIACAO" THEN "NEGOTIATION_FS"
            WHEN rs.participant_role = "EXECUTIVO_ASSOCIADO" THEN "BUSINESS_OPERATOR_SUPPLY_CONVERSION_FS"
            ELSE "DEMAND_CONVERSION_FS"
        END AS replacement_incentive_system,
        IF(rs.is_3p_partnership IS TRUE, "COMPANY", "AGENT") AS revenue_receiver_type,
        COALESCE(
            NULLIF(
                COALESCE(rs.remuneration_baseline, 0)
                + COALESCE(rs.remuneration_bonus, 0)
                + COALESCE(rs.campaign_bonus, 0)
                + COALESCE(rs.advance_bonus, 0),
                0
            ),
            rs.final_revenue_share_percentage
        ) AS revenue_percentage,
        rs.ts_created
    FROM
        nazare_revenue_share AS rs
    WHERE
        rs.participant_role NOT IN ('CIQ', 'SUPPLY')
        AND (
            COALESCE(rs.remuneration_baseline, 0) + COALESCE(rs.remuneration_bonus, 0) + COALESCE(rs.campaign_bonus, 0) > 0
            OR NOT ROUND(COALESCE(rs.tqc_bonus, 0), 4) = ROUND(rs.final_revenue_share_percentage, 4)
            OR rs.is_3p_partnership IS TRUE
        )
),
participant_role AS (
    SELECT
        mp.uuid_person,
        mp.id_user,
        mp.profile,
        ROW_NUMBER() OVER(PARTITION BY mp.uuid_person ORDER BY IF(mp.status = 'ACTIVE', 1, 0) DESC, mp.ts_updated DESC) = 1 AS is_last_agent_by_person
    FROM
        datalake_agent_accreditation.agent AS mp
    WHERE
        mp.uuid_person IS NOT NULL
),
nazare_earnings AS (
    SELECT
        XXHASH64(ui.id_revenue_share, ui.incentive_system, "NAZARE") AS id_partner_payment,
        sources.id AS id_earning_source,
        ui.id_revenue_share,
        rs.id_house,
        NULL AS id_contract,
        COALESCE(oa.id_sales_flow, op.id_sales_flow) AS id_sales_flow,
        COALESCE(oa.id_offer, op.id_offer) AS id_offer,
        oa.id_business_unit,
        COALESCE(pt_person.id_tier, pt_company.id_tier) AS id_tier,
        oa.id_user,
        oa.uuid_person,
        op.uuid_company,
        COALESCE(ui.replacement_incentive_system, ui.incentive_system) AS incentive_system,
        NULL AS calculated_from,
        "SALE" AS business_context,
        CASE
            WHEN rs.participant_role IN ("THIRD_PARTY_AGENT") OR rs.is_3p_partnership IS TRUE THEN "THIRD_PARTY_AGENT"
            WHEN rs.participant_role IN ("CIQ", "SUPPLY") AND pr.profile = "PRO_ACQUIRER" THEN pr.profile
            ELSE "AUTONOMOUS_BROKERAGE_AGENT"
        END AS participant_role,
        CASE
            WHEN UPPER(rs.tier_name) IN ("DIAMANTE", "DIAMOND") THEN "DIAMOND"
            WHEN UPPER(rs.tier_name) IN ("OURO", "GOLD") THEN "GOLD"
            WHEN UPPER(rs.tier_name) IN ("PRATA", "SILVER") THEN "SILVER"
            WHEN UPPER(rs.tier_name) IN ("BRONZE") THEN "BRONZE"
        END tier_name,
        ui.revenue_receiver_type,
        "NAZARE" AS revenue_source,
        IF(rs.participant_role IN ('CIQ', 'SUPPLY'), 'SUPPLY', 'DEMAND') AS revenue_role,
        NULL AS revenue_share_type,
        NULL AS revenue_share_value,
        COALESCE(oa.brokerage_fee, op.brokerage_fee, rs.brokerage) AS brokerage_fee,
        COALESCE(oa.brokerage_fee, op.brokerage_fee, rs.brokerage) * rs.sale_price AS brokerage_amount,
        rs.sale_price AS ticket_base_amount,
        ui.revenue_percentage,
        IF(
            ui.incentive_system IN ("DEMAND_CONVERSION_FS", "DEMAND_ACQUISITION_FS") AND b.incentive_system IS NOT NULL,
            ROUND((ui.revenue_percentage * rs.gross_remuneration)/rs.final_revenue_share_percentage, 4),
            rs.gross_remuneration
        ) AS revenue_amount,
        COALESCE(rs.offer_category LIKE "%LEAD_GEN%", FALSE) AS is_3p_lead_gen_offer,
        COALESCE(rs.participant_role = "EXECUTIVO_VISITAS_FIFTY", FALSE) AS is_fifty_revenue_share,
        NULL AS is_crcc_revenue_share,
        NULL AS is_tier_revenue_share,
        NULL AS is_manual_calculation,
        COALESCE(pt_person.dt_validity_started, pt_company.dt_validity_started) AS dt_tier_reference,
        COALESCE(oa.ts_contract_signed, op.ts_contract_signed) AS ts_contract_signed,
        ui.ts_created,
        rs.ts_updated
    FROM
        union_nazare_incentives AS ui
    JOIN
        nazare_revenue_share AS rs
            ON rs.id_revenue_share = ui.id_revenue_share
    LEFT JOIN
        union_nazare_incentives AS b
            ON ui.id_revenue_share = b.id_revenue_share
            AND b.incentive_system IN ("DEMAND_CONVERSION_FS", "DEMAND_ACQUISITION_FS")
            AND ui.incentive_system <> b.incentive_system
    LEFT JOIN
        nazare_offer_agent AS oa
            ON oa.id_offer_agent = rs.id_offer_agent
    LEFT JOIN
        nazare_offer_partner AS op
            ON op.id_offer_partner = rs.id_offer_partner
    LEFT JOIN
        datalake_big_agent_clean.earning_sources AS sources
            ON sources.uuid_earning_source = rs.uuid_earning_source
    LEFT JOIN
        participant_role AS pr
            ON pr.uuid_person = oa.uuid_person
            AND pr.is_last_agent_by_person IS TRUE
    LEFT JOIN
        datalake_big_agent.partner_tier AS pt_person
            ON pt_person.uuid_person = oa.uuid_person
            AND pt_person.tier_name = rs.tier_name
            AND DATE(ui.ts_created) BETWEEN pt_person.dt_validity_started AND pt_person.dt_validity_ended
    LEFT JOIN
        datalake_big_agent.partner_tier AS pt_company
            ON pt_company.uuid_company = op.uuid_company
            AND pt_company.tier_name = rs.tier_name
            AND DATE(ui.ts_created) BETWEEN pt_company.dt_validity_started AND pt_company.dt_validity_ended
)
SELECT
    e.id_earning AS id_partner_payment,
    e.id_earning,
    e.id_earning_source,
    e.id_revenue_share,
    e.id_house,
    e.id_contract,
    e.id_sales_flow,
    e.id_offer,
    e.id_offer_business_unit AS id_business_unit,
    e.id_tier,
    person.id_user,
    e.uuid_person,
    e.uuid_company,
    e.incentive_system,
    e.calculated_from,
    e.business_context,
    CASE
        WHEN pr.profile = "REDE"
            OR e.uuid_company IS NOT NULL
            THEN "THIRD_PARTY_AGENT"
        ELSE pr.profile
    END AS participant_role,
    e.tier_name,
    e.external_receiver_type AS revenue_receiver_type,
    "BIG_AGENT" AS revenue_source,
    CASE
        WHEN SPLIT(e.incentive_system, '_')[0] = "SUPPLY" THEN "SUPPLY"
        WHEN SPLIT(e.incentive_system, '_')[0] = "DEMAND" THEN "DEMAND"
    END AS revenue_role,
    e.revenue_share_type,
    e.revenue_share_value,
    e.base_amount AS ticket_base_amount,
    e.brokerage_fee,
    ROUND(e.calculation_base_amount, 4) AS brokerage_amount,
    ROUND(e.revenue_amount, 4) AS revenue_amount,
    ROUND(e.revenue_percentage, 4) AS revenue_percentage,
    NULL AS is_3p_lead_gen_offer,
    e.revenue_share_type = "FIFTY" AS is_fifty_revenue_share,
    e.revenue_share_type = "CRCC" AS is_crcc_revenue_share,
    e.revenue_share_type = "TIER" AS is_tier_revenue_share,
    e.is_manual_calculation,
    e.dt_tier_reference,
    e.ts_contract_signed,
    e.ts_created,
    e.ts_updated
FROM
    datalake_big_agent.earnings AS e
LEFT JOIN
    datalake_person.person_sks AS person
        ON e.uuid_person = person.uuid_person
LEFT JOIN
    participant_role AS pr
        ON pr.uuid_person = e.uuid_person
        AND pr.is_last_agent_by_person IS TRUE
WHERE
    e.earning_status = 'CALCULATED'
    AND DATE(e.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
UNION
SELECT
    e.id_partner_payment,
    NULL AS id_earning,
    e.id_earning_source,
    e.id_revenue_share,
    e.id_house,
    e.id_contract,
    e.id_sales_flow,
    e.id_offer,
    e.id_business_unit,
    e.id_tier,
    e.id_user,
    e.uuid_person,
    e.uuid_company,
    e.incentive_system,
    e.calculated_from,
    e.business_context,
    e.participant_role,
    e.tier_name,
    e.revenue_receiver_type,
    e.revenue_source,
    e.revenue_role,
    e.revenue_share_type,
    e.revenue_share_value,
    e.ticket_base_amount,
    e.brokerage_fee,
    e.brokerage_amount,
    e.revenue_amount,
    e.revenue_percentage,
    e.is_3p_lead_gen_offer,
    e.is_fifty_revenue_share,
    e.is_crcc_revenue_share,
    e.is_tier_revenue_share,
    e.is_manual_calculation,
    e.dt_tier_reference,
    e.ts_contract_signed,
    e.ts_created,
    e.ts_updated
FROM
    nazare_earnings AS e
