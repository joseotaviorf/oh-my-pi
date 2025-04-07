SELECT 
    id AS sk_offer_topic_message,
    comment,
    iteration,
    actor_role,
    proposed_rent_value,
    ts_created,
    ts_updated
FROM
    datalake_rental_transact_clean.offer_topic_message