SELECT 
    id,
    user_id AS id_user,
    offer_id AS id_offer,
    financing_options_id AS id_financing_options,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM 
    datalake_risk_and_mortgage_raw.credit_application
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
