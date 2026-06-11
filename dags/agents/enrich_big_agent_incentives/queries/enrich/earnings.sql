WITH new_earnings_filtered AS (
    SELECT
        ne.id,
        ne.id_earning_source,
        ne.id_revenue_share,
        ne.id_external_receiver,
        ne.id_author,
        ne.author_role,
        ne.external_receiver_type,
        ne.incentive_system,
        ne.calculated_from,
        ne.currency,
        ne.status,
        ne.reason,
        ne.revenue_amount,
        ne.revenue_percentage,
        ne.ts_created,
        ne.ts_updated
    FROM
        datalake_big_agent_clean.new_earnings AS ne
    WHERE
        DATE(ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT 
    ne.id AS id_earning,
    ne.id_earning_source,
    ne.id_revenue_share,
    IF(es.external_domain_type = 'RENT_CONTRACT', es.id_external_domain, NULL) AS id_contract,
    IF(es.external_domain_type = 'SALES_FLOW', es.id_external_domain, NULL) AS id_sales_flow,
    IF(ne.author_role <> "SYSTEM", ne.id_author, NULL) AS id_author,
    es.uuid_external_cart AS uuid_cart,
    IF(ne.external_receiver_type = "COMPANY", ne.id_external_receiver, NULL) AS uuid_company,
    IF(ne.external_receiver_type = "AGENT", ne.id_external_receiver, NULL) AS uuid_person,
    CASE
        WHEN es.external_domain_type = 'RENT_CONTRACT' THEN "RENT"
        WHEN es.external_domain_type = 'SALES_FLOW' THEN "SALE"
    END AS business_context,
    es.external_domain_type AS domain_type,
    ne.incentive_system,
    ne.calculated_from,
    ne.currency,
    ne.status AS earning_status,
    ne.reason AS earning_status_reason,
    es.status AS earning_source_status,
    es.failure_reason AS earning_source_status_reason,
    ROUND(es.base_amount, 2) AS base_amount,
    ROUND(es.revenue_share_total_amount, 2) AS revenue_share_total_amount,
    ROUND(ne.revenue_amount, 2) AS revenue_amount,
    ROUND(ne.revenue_percentage, 2) AS revenue_percentage,
    ne.author_role = "SYSTEM" AS is_authored_by_system,
    ne.ts_created,
    ne.ts_updated,
    DATE(ne.ts_created) AS dt_load,
    YEAR(ne.ts_created) AS year,
    MONTH(ne.ts_created) AS month,
    DAY(ne.ts_created) AS day
FROM 
    new_earnings_filtered AS ne
JOIN 
    datalake_big_agent_clean.earning_sources AS es 
        ON es.id = ne.id_earning_source