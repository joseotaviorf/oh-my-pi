SELECT
    NULLIF(city_group, '') AS city_group,
    NULLIF(rental_administrator, '') AS rental_administrator,
    NULLIF(business_type, '') AS business_type,
    NULLIF(rent_flow_origin, '') AS rent_flow_origin,
    CAST(REPLACE(NULLIF(visits_booked, ''), ',', '') AS FLOAT) AS visits_booked,
    CAST(REPLACE(NULLIF(visits_completed, ''), ',', '') AS FLOAT) AS visits_completed,
    CAST(REPLACE(NULLIF(offers_submitted, ''), ',', '') AS FLOAT) AS offers_submitted,
    CAST(REPLACE(NULLIF(offers_accepted, ''), ',', '') AS FLOAT) AS offers_accepted,
    CAST(REPLACE(NULLIF(documentation_sent, ''), ',', '') AS FLOAT) AS documentation_sent,
    CAST(REPLACE(NULLIF(evaluation_started, ''), ',', '') AS FLOAT) AS evaluation_started,
    CAST(REPLACE(NULLIF(evaluation_positive, ''), ',', '') AS FLOAT) AS evaluation_positive,
    CAST(REPLACE(NULLIF(credit_approved, ''), ',', '') AS FLOAT) AS credit_approved,
    CAST(REPLACE(NULLIF(contracts_signed, ''), ',', '') AS FLOAT) AS contracts_signed,
    CAST(NULLIF(date, '') AS DATE) AS date
FROM
    datalake_gsheets_raw.rent_demand_budget_2025