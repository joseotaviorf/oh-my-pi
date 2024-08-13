SELECT
    city_group,
    business_type,
    rent_flow_origin,
    rental_administrator,
    visits_booked,
    visits_completed,
    offers_submitted,
    offers_accepted,
    evaluation_started,
    evaluation_positive,
    documentation_sent,
    credit_approved,
    contracts_signed,
    TO_DATE(date) AS dt_target
FROM
    datalake_gsheets_raw.demand_targets_2024
