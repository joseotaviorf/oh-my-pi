SELECT
    city_group,
    business_type,
    rent_flow_origin,
    NULLIF(rental_administrator, '') AS rental_administrator,
    visits_booked,
    visits_completed,
    offers_submitted,
    offers_accepted,
    evaluation_started,
    evaluation_positive,
    documentation_sent,
    credit_approved,
    contracts_signed,
    'FORECAST' AS target_type,
    dt_target
FROM
    datalake_gsheets.rental_demand_coincident_targets
UNION ALL
SELECT
    city_group,
    business_type,
    rent_flow_origin,
    NULLIF(rental_administrator, '') AS rental_administrator,
    visits_booked,
    visits_completed,
    offers_submitted,
    offers_accepted,
    evaluation_started,
    evaluation_positive,
    documentation_sent,
    credit_approved,
    contracts_signed,
    'BUDGET' AS target_type,
    dt_budget AS dt_target
FROM
    datalake_gsheets_clean.rent_demand_budget_2024