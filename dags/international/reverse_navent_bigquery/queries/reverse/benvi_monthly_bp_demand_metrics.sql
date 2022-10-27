SELECT 
    YEAR(dt_month_started) AS base_year,
    dt_month_started AS month_start,
    country_code AS country_name,
    city_group,
    new_tenant_prospects,
    tenant_prospects,
    visits_booked,
    offers_submitted,
    contracts_signed,
    visits_booked_target,
    visits_completed_target,
    offers_submitted_target,
    offers_accepted_target,
    credits_approved_target,
    contracts_signed_target,
    budget_target,
    actual_cost
FROM
    datalake_mexico_rent_demand.monthly_demand_funnel