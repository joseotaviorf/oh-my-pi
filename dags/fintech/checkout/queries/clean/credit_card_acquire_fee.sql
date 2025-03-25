SELECT 
    id,
    acquire_name,
    card_brand,
    fee_percentage,
    installments,
    created_at AS ts_created,
    disabled_at AS ts_disabled
FROM 
    datalake_checkout_raw.credit_card_acquire_fee
