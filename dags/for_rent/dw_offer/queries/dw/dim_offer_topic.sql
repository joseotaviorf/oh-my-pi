SELECT 
    id AS sk_offer_topic,
    status,
    type,
    ts_created,
    ts_updated,
    NOW() AS ts_load
FROM
    datalake_rental_transact_clean.offer_topic