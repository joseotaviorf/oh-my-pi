SELECT 
    id,
    amount,
    success,
    payload,
    psp_reference,
    event_code,
    merchant_account_code,
    DATE(event_date) as dt_event
FROM 
    datalake_checkout_homolog_raw.webhook