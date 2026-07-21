WITH new_earnings_filtered AS (
    SELECT
        ne.id,
        ne.id_earning_source,
        ne.id_revenue_share,
        ne.id_external_receiver,
        ne.id_author,
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
        ) AS calculation_status
    FROM 
        datalake_big_agent_clean.earning_sources AS es
)
SELECT DISTINCT
    ne.id AS id_earning,
    ue.id_unresolved_earning,
    ei.id AS id_earning_invalidation,
    ei.id_replaced_by AS id_replacement_earning,
    ne.id_earning_source,
    ne.id_revenue_share,
    es.id_contract,
    es.id_sales_flow,
    IF(
        GET_JSON_OBJECT(ei.author, "$.type") = 'PERSON', 
        GET_JSON_OBJECT(ei.author, "$.id"), 
        NULL
    ) AS id_invalidation_author,
    IF(ne.author_role <> "SYSTEM", ne.id_author, NULL) AS id_author,
    COALESCE(person_tier.id_tier, rs.id_tier) AS id_tier,
    person_tier.id_partner_tier,
    rs.id_incentive_engine,
    es.uuid_cart,
    IF(ne.external_receiver_type = "COMPANY", ne.id_external_receiver, NULL) AS uuid_company,
    IF(ne.external_receiver_type = "AGENT", ne.id_external_receiver, NULL) AS uuid_person,
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
    rs.revenue_share_type,
    person_tier.tier_name,
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
    ne.dt_payment_due,
    ue.ts_solved AS ts_unresolved_earning_solved,
    ne.ts_created,
    ei.ts_invalidated,
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
        ON ue.id_earning = ne.id
        AND ue.is_first_solved_by_earning IS TRUE
LEFT JOIN
    datalake_big_agent.partner_tier AS person_tier
        ON ne.external_receiver_type = 'AGENT'
        AND person_tier.uuid_person = ne.id_external_receiver
        AND person_tier.incentive_system = ne.incentive_system
        AND person_tier.is_valid IS TRUE
        AND DATE(ne.ts_created) BETWEEN person_tier.dt_validity_started AND person_tier.dt_validity_ended