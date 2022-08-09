SELECT 
    id_offer AS sk_offer,
    id_house AS sk_house,
    id_buyer AS sk_buyer,
    id_visit AS sk_visit,
    id_booking AS sk_listing,
    current_payment_method,
    planned_payment_method,
    monday_status,
    payment_model,
    itbi_price AS itbi_value,
    registry_price,
    payment_entry_amount AS down_payment_value,
    financing_value,
    fgts_value,
    earnest_value,
    sale_price_agreed,
    is_ccv_canceled
FROM 
    datalake_money_laundering_prevention.transaction