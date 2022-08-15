SELECT 
    so.id_offer,
    so.id_house,
    so.id_buyer,
    so.id_vendas,
    so.id_sale_flow AS id_sale_flow_firestore,
    b.id_visit,
    b.id AS id_booking,
    so.current_payment_method,
    so.planned_payment_method,
    so.offer_status,
    so.payment_model,
    so.itbi_price,
    so.registry_price,
    so.payment_entry_amount,
    so.financing_value,
    so.fgts_value,
    so.earnest_value,
    so.sale_price_agreed,
    so.is_ccv_canceled
FROM 
    datalake_offer.sale_offer so
LEFT JOIN datalake_booking.booking b
    ON b.id_visitor = so.id_buyer
        AND b.id_house = so.id_house
        AND b.visit_intent = 'SALE'