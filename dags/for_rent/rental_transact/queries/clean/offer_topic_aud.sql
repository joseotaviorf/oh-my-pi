SELECT
    id,
    offer_topic_uuid AS uuid_offer_topic,
    offer_id AS id_offer,
    firestore_id AS id_firestore,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    status,
    type,
    status_mod AS mod_status,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_transact_raw.offer_topic_aud