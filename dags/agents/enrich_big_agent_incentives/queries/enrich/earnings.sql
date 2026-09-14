WITH new_earnings_filtered AS (
    SELECT
        ne.id,
        ne.id_earning_source,
        ne.id_revenue_share,
        ne.id_tier_earning_configuration,
        ne.id_author,
        ne.id_external_receiver,
        IF(ne.external_receiver_type = "COMPANY", ne.id_external_receiver, NULL) AS uuid_company,
        IF(ne.external_receiver_type = "AGENT", ne.id_external_receiver, NULL) AS uuid_person,
        ne.author_role,
        ne.author_channel,
        ne.author_on_behalf_of_role,
        ne.external_receiver_type,
        ne.incentive_system,
        ne.calculated_from,
        ne.currency,
        ne.status,
        ne.reason,
        ne.revenue_amount,
        ne.revenue_percentage,
        CASE
            WHEN ne.status = "CALCULATED" AND ne.external_receiver_type = "AGENT" THEN SUM(CASE WHEN ne.status = "CALCULATED" AND ne.external_receiver_type = "AGENT" THEN ne.revenue_percentage ELSE 0 END) OVER(PARTITION BY id_earning_source, incentive_system)
            ELSE NULL
        END AS brokerage_fee_by_incentive_system,
        ne.dt_payment_due,
        ne.ts_created,
        ne.ts_updated
    FROM
        datalake_big_agent_clean.new_earnings AS ne
    WHERE
        DATE(ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
earning_sources AS (
    SELECT
        id,
        IF(es.external_domain_type = 'RENT_CONTRACT', es.id_external_domain, NULL) AS id_contract,
        IF(es.external_domain_type = 'SALES_FLOW', es.id_external_domain, NULL) AS id_sales_flow,
        es.uuid_external_cart AS uuid_cart,
        CASE
            WHEN es.external_domain_type = 'RENT_CONTRACT' THEN "RENT"
            WHEN es.external_domain_type = 'SALES_FLOW' THEN "SALE"
        END AS business_context,
        es.external_domain_type AS domain_type,
        es.status AS earning_source_status,
        es.failure_reason AS earning_source_status_reason,
        es.base_amount,
        es.revenue_share_total_amount,
        FROM_JSON(
            incentive_systems_calculation_status,
            'MAP<STRING,STRING>'
        ) AS calculation_status,
        es.ts_sent_to_finance
    FROM
        datalake_big_agent_clean.earning_sources AS es
),
sales_flow_offer AS (
    SELECT
        sf.id AS id_sales_flow,
        o.id_firestore AS id_offer,
        h.id_external AS id_house,
        o.id_hub AS id_business_unit,
        fee.brokerage_fee,
        MAX(ccv.ts_signed) AS ts_contract_signed
    FROM
        datalake_sales_flow_clean.sales_flow AS sf
    LEFT JOIN
        datalake_sales_flow_clean.offer AS o
            ON o.id_sales_flow = sf.id
    LEFT JOIN
        datalake_sales_flow_clean.house AS h
            ON h.id = sf.id_house
    LEFT JOIN
        datalake_sales_flow_clean.brokerage AS fee
            ON fee.id_sales_flow = sf.id
    LEFT JOIN
        datalake_sales_flow_clean.ccv AS ccv
            ON ccv.id_sales_flow = sf.id
            AND ccv.ts_signed IS NOT NULL
    GROUP BY 1, 2, 3, 4, 5
)
SELECT DISTINCT
    ne.id AS id_earning,
    ue.id_unresolved_earning,
    ei.id AS id_earning_invalidation,
    ei.id_replaced_by AS id_replacement_earning,
    ne.id_earning_source,
    ne.id_revenue_share,
    ne.id_tier_earning_configuration,
    es.id_contract,
    es.id_sales_flow,
    IF(
        GET_JSON_OBJECT(ei.author, "$.type") = 'PERSON',
        GET_JSON_OBJECT(ei.author, "$.id"),
        NULL
    ) AS id_invalidation_author,
    IF(ne.author_role <> "SYSTEM", ne.id_author, NULL) AS id_author,
    COALESCE(rs.id_tier, person_tier.id_tier) AS id_tier,
    person_tier.id_partner_tier,
    COALESCE(rs.id_incentive_engine, tier.id_incentive_engine) AS id_incentive_engine,
    COALESCE(sf.id_house, c.id_house) AS id_house,
    sf.id_offer,
    sf.id_business_unit AS id_offer_business_unit,
    tier.id_business_unit AS id_partner_tier_business_unit,
    es.uuid_cart,
    ne.uuid_company,
    ne.uuid_person,
    es.business_context,
    es.domain_type,
    ne.incentive_system,
    ne.calculated_from,
    ne.currency,
    ne.external_receiver_type,
    ne.status AS earning_status,
    ne.reason AS earning_status_reason,
    ei.reason AS invalidation_reason,
    ei.invalidation_description,
    ue.reason AS unresolved_earning_reason,
    rs.performance_evaluation_period,
    rs.tier_validity_period,
    rs.revenue_share_type,
    rs.revenue_share_value,
    person_tier.tier_name,
    es.base_amount,
    es.revenue_share_total_amount,
    CASE
        WHEN es.business_context = "SALE" THEN sf.brokerage_fee
        WHEN es.business_context = "RENT" THEN ne.brokerage_fee_by_incentive_system
    END AS brokerage_fee,
    CASE
        WHEN ne.calculated_from = 'REVENUE_SHARE_TOTAL_AMOUNT' THEN es.revenue_share_total_amount
        WHEN ne.calculated_from = 'BASE_AMOUNT' THEN es.base_amount
        ELSE es.base_amount
    END AS calculation_base_amount,
    ne.revenue_amount AS revenue_amount,
    ne.revenue_percentage AS revenue_percentage,
    ne.author_role,
    ne.author_channel,
    ne.author_on_behalf_of_role,
    ne.author_role = "SYSTEM" AS is_authored_by_system,
    ne.reason = "MANUAL_CALCULATION" AS is_manual_calculation,
    ne.status = 'INVALIDATED' OR ei.id IS NOT NULL AS is_invalid,
    ne.status = 'CALCULATED' AS is_calculated,
    CAST(NULL AS BOOLEAN) AS is_3p_lead_gen_offer,
    rs.revenue_share_type = "FIFTY" AS is_fifty_revenue_share,
    rs.revenue_share_type = "CRCC" AS is_crcc_revenue_share,
    rs.revenue_share_type = "TIER" AS is_tier_revenue_share,
    ne.dt_payment_due,
    person_tier.dt_validity_started AS dt_tier_reference,
    ue.ts_solved AS ts_unresolved_earning_solved,
    ne.ts_created,
    ei.ts_invalidated,
    es.ts_sent_to_finance,
    COALESCE(sf.ts_contract_signed, c.ts_signed) AS ts_contract_signed,
    ne.ts_updated,
    YEAR(ne.ts_created) AS year,
    MONTH(ne.ts_created) AS month,
    DAY(ne.ts_created) AS day
FROM
    new_earnings_filtered AS ne
JOIN
    earning_sources AS es
        ON es.id = ne.id_earning_source
LEFT JOIN
    datalake_big_agent_clean.earning_invalidations AS ei
        ON ei.id_earning = ne.id
LEFT JOIN
    datalake_big_agent.revenue_share AS rs
        ON rs.id_revenue_share = ne.id_revenue_share
LEFT JOIN
    datalake_big_agent.unresolved_earnings AS ue
        ON ue.id_earning_source = ne.id_earning_source
        AND ue.id_external_receiver = ne.id_external_receiver
        AND ue.external_receiver_type = ne.external_receiver_type
        AND ue.incentive_system = ne.incentive_system
        AND ue.is_first_solved_by_earning IS TRUE
LEFT JOIN
    datalake_big_agent.partner_tier AS person_tier
        ON person_tier.uuid_person = ne.uuid_person
        AND person_tier.incentive_system = ne.incentive_system
        AND person_tier.is_valid IS TRUE
        AND DATE(ne.ts_created) BETWEEN person_tier.dt_validity_started AND person_tier.dt_validity_ended
LEFT JOIN
    datalake_big_agent.tier_rule AS tier
        ON tier.id_tier = person_tier.id_tier
LEFT JOIN
    sales_flow_offer AS sf
        ON sf.id_sales_flow = es.id_sales_flow
LEFT JOIN
    datalake_ebdb_clean.contract AS c
        ON c.id = es.id_contract
