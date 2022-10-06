--BRANDING COSTS
SELECT
    id,
    id_date,
    id_rule_city_group_rent,
    id_rule_city_group_sale,
    id_rule_cost_center,
    email,
    team,
    entry_type,
    invoice_number,
    cnpj,
    vendor_name,
    description,
    campaign_name,
    cost_category,
    cost_subcategory,
    action,
    business_context,
    has_city_group_share,
    has_cost_center_share,
    cost_center,
    city_group,
    cost,
    CASE 
        WHEN LOWER(cost_center) LIKE '%sale%' THEN 'Sale'
        ELSE 'Rental' 
    END AS planning_business_context,
    NULL AS budget,
    ts_entry,
    dt_invoice,
    dt_service_started,
    dt_service_ended
FROM
    datalake_marketing_costs.offline_manual_costs
UNION ALL
--PLANNING COSTS TARGETS
SELECT 
    NULL AS id,
    INT(REPLACE(STRING(dt_budget), '-', '')) AS id_date,
    NULL AS id_rule_city_group_rent,
    NULL AS id_rule_city_group_sale,
    NULL AS id_rule_cost_center,
    NULL AS email,
    NULL AS team,
    NULL AS entry_type,
    NULL AS invoice_number,
    NULL AS cnpj,
    NULL AS vendor_name,
    NULL AS description,
    NULL AS campaign_name,
    NULL AS cost_category,
    NULL AS cost_subcategory,
    NULL AS action,
    NULL AS business_context,
    NULL AS has_city_group_share,
    NULL AS has_cost_center_share,
    NULL AS cost_center,
    city_group,
    NULL AS cost,
    business_context AS planning_business_context,
    budget AS budget,
    NULL AS ts_entry,
    NULL AS dt_invoice,
    NULL AS dt_service_started,
    NULL AS dt_service_ended
FROM
    datalake_marketing_offline_costs_clean.marketing_offline_budget