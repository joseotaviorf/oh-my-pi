SELECT
    STRING(NULLIF(city_group,'')) AS city_group,
    STRING(NULLIF(cost_category,'')) AS cost_category,
    STRING(NULLIF(business_context,'')) AS business_context,
    FLOAT(NULLIF(budget,'')) AS budget,
    DATE(NULLIF(date, '')) AS dt_budget
FROM
    datalake_marketing_offline_costs_raw.marketing_offline_budget
