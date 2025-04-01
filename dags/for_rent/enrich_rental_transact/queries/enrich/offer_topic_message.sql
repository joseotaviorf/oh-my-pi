SELECT 
    id AS id_topic_message,
    uuid_offer_topic_message,
    id_offer_topic,
    id_firestore,
    iteration,
    MAX(iteration) OVER(PARTITION BY id_offer_topic) AS max_topic_iteration,
    actor_role,
    proposed_rent_value,
    comment,
    ts_created,
    ts_updated
FROM
    datalake_rental_transact_clean.offer_topic_message