SELECT 
    YEAR(dt_week_started) AS base_year,
    dt_week_started AS week_start,
    country_code AS country_name,
    city_group,
    new_tenant_prospects,
    tenant_prospects,
    visits_booked,
    visits_completed,
    offer_submitted,
    offer_accepted,
    credit_approved,
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
    datalake_mexico_rent_demand_funnel.weekly_demand_flow_metrics