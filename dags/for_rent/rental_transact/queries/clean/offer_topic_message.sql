SELECT
    id,
    offer_topic_message_uuid AS uuid_offer_topic_message,
    offer_topic_id AS id_offer_topic,
    firestore_id AS id_firestore,
    comment,
    iteration,
    actor_role,
    proposed_rent_value,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_transact_raw.offer_topic_message