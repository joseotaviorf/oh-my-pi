SELECT
    e.id_earning AS sk_earning,
    e.id_replacement_earning AS sk_replacement_earning,
    e.id_earning_source AS sk_earning_source,
    e.id_contract AS sk_contract,
    e.id_sales_flow AS sk_sales_flow,
    author.sk_person AS sk_author,
    invalidation_author.sk_person AS sk_invalidation_author,
    e.id_tier AS sk_tier,
    e.id_partner_tier AS sk_partner_tier,
    person.sk_person AS sk_person,
    cart.id AS sk_cart,
    COALESCE(cb.sk_broker, -1) AS sk_broker,
    e.incentive_system,
    e.invalidation_reason,
    e.invalidation_description,
    e.unresolved_earning_reason,
    e.revenue_share_type,
    e.tier_name AS partner_tier_name,
    e.calculation_base_amount,
    e.revenue_amount,
    e.revenue_percentage,
    e.id_unresolved_earning IS NOT NULL AS has_unresolved_earning,
    e.domain_type = 'RENT_CONTRACT' AS is_rent_contract,
    e.domain_type = 'SALES_FLOW' AS is_sales_flow,
    e.is_calculated,
    e.is_invalid,
    e.invalidation_reason = 'RECALCULATED' AS is_invalid_for_recalculation_reason,
    e.invalidation_reason = 'WRONG_REVENUE_AMOUNT' AS is_invalid_for_amount_wrong_reason,
    e.id_replacement_earning IS NOT NULL AS is_replaced,
    e.earning_status_reason = "MANUAL_CALCULATION" AS is_manual_calculation,
    e.is_authored_by_system,
    e.dt_payment_due,
    e.ts_unresolved_earning_solved,
    e.ts_invalidated,
    e.ts_created,
    e.ts_updated,
    NOW() AS ts_load,
    e.year,
    e.month,
    e.day
FROM
    datalake_big_agent.earnings AS e
LEFT JOIN
    datalake_person.person_sks AS person
        ON e.uuid_person = person.uuid_person
LEFT JOIN
    datalake_person.person_sks AS author
        ON e.id_author = author.uuid_person
LEFT JOIN
    datalake_person.person_sks AS invalidation_author
        ON e.id_invalidation_author = invalidation_author.uuid_person
LEFT JOIN
    datalake_cart_system_clean.cart AS cart
        ON e.uuid_cart = cart.uuid_cart
LEFT JOIN
    core_brokers.brokers AS cb
        ON e.uuid_company = cb.uuid_company
WHERE
    e.invalidation_reason <> "PRODUCT_TESTING"
    AND DATE(e.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')