SELECT
    id,
    offer_topic_uuid AS uuid_offer_topic,
    offer_id AS id_offer,
    firestore_id AS id_firestore,
    status,
    type,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_transact_raw.offer_topic