SELECT 
    id,
    external_id AS id_external,
    credit_application_id AS id_credit_application,
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
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM 
    datalake_risk_and_mortgage_raw.bank_application
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
