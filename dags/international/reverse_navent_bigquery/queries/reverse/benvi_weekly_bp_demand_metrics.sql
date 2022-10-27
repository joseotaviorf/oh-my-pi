SELECT 
    YEAR(dt_week_started) AS base_year,
    dt_week_started AS week_start,
    country_code AS country_name,
    city_group,
    new_tenant_prospects,
    tenant_prospects,
    visits_booked,
    visits_completed,
    offers_submitted,
    offers_accepted,
    credits_approved,
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
    datalake_mexico_rent_demand_funnel.weekly_demand_flow_metrics