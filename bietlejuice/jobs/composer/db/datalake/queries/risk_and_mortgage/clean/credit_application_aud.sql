SELECT 
    id,
    user_id AS id_user,
    offer_id AS id_offer,
    financing_options_id AS id_financing_options,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    status,
    financing_options_id_mod AS mod_id_financing_options,
    offer_id_mod AS mod_id_offer,
    status_mod AS mod_status,
    created_at AS ts_created,
    year,
    month,
    day
FROM 
    datalake_risk_and_mortgage_raw.credit_application_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
