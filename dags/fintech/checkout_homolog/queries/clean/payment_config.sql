SELECT 
    id,
    requester_id AS id_requester,
    bank_account_id AS id_bank_account,
    status,
    name,
    payment_method,
    exhibition_name,
    document,
    pix_key
FROM 
    datalake_checkout_homolog_raw.payment_config