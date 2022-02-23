SELECT
    city, 
    model,
    adm_fee_new_rental,
    adm_fee_ongoing_rental,
    CAST(avg_ticket_new_rental AS FLOAT) AS avg_ticket_new_rental,
    CAST(avg_ticket_ongoing_rental AS FLOAT) AS avg_ticket_ongoing_rental,
    bookerage_fee,
    CAST(contract_signed AS FLOAT) AS contract_signed,
    CAST(ended_rentals AS FLOAT) AS ended_rentals,
    CAST(new_rentals AS FLOAT) AS new_rentals,
    CAST(ongoing_rentals AS FLOAT) AS ongoing_rentals,
    CAST(fy AS INT) As year,
    CAST(quarter AS INT) AS quarter,
    CAST(month AS INT) AS month
FROM
    datalake_gsheets_raw.planning_rental_financial_targets