SELECT 
    YEAR(dt_month_started) AS base_year,
    dt_month_started AS month_start,
    country_code AS country_name,
    city_group,
    new_tenant_prospects,
    tenant_prospects,
    visits_booked,
    offer_submitted,
    contract_signed,
    visits_booked_target,
    visits_completed_target,
    offer_submitted_target,
    offer_accepted_target,
    credit_approved_target,
    contract_signed_target,
    budget_target,
    actual_cost
FROM
    datalake_mexico_rent_demand_funnel.monthly_demand_flow_metrics