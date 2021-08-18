SELECT 
    id,
    external_id AS id_external,
    credit_application_id AS id_credit_application,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    bank AS bank_name,
    status,
    annual_fee,
    requested_amount,
    approved_amount,
    requested_installments,
    approved_installments,
    first_installment_amount,
    last_installment_amount,
    response_from_bank,
    dates,
    values,
    status_mod AS mod_status,
    dates_mod  AS mod_dates,
    values_mod AS mod_values,
    created_at AS ts_created,
    year,
    month,
    day
FROM 
    datalake_risk_and_mortgage_raw.bank_application_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
