SELECT
    city_group,
    business_type,
    rent_flow_origin,
    rental_administrator,
    CAST(REPLACE(visits_booked, ',', '') AS DECIMAL(14,6)) AS visits_booked,
    CAST(REPLACE(visits_completed, ',', '') AS DECIMAL(14,6)) AS visits_completed,
    CAST(REPLACE(offers_submitted, ',', '') AS DECIMAL(14,6)) AS offers_submitted,
    CAST(REPLACE(offers_accepted, ',', '') AS DECIMAL(14,6)) AS offers_accepted,
    CAST(REPLACE(evaluation_started, ',', '') AS DECIMAL(14,6)) AS evaluation_started,
    CAST(REPLACE(evaluation_positive, ',', '') AS DECIMAL(14,6)) AS evaluation_positive,
    CAST(REPLACE(documentation_sent, ',', '') AS DECIMAL(14,6)) AS documentation_sent,
    CAST(REPLACE(credit_approved, ',', '') AS DECIMAL(14,6)) AS credit_approved,
    CAST(REPLACE(contracts_signed, ',', '') AS DECIMAL(14,6)) AS contracts_signed,
    TO_DATE(date, 'yyyy-MM-dd') AS dt_budget
FROM
    datalake_gsheets_raw.rent_demand_budget_2024
