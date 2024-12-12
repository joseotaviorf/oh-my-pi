SELECT
    id,
    offer_topic_message_uuid AS uuid_offer_topic_message,
    offer_topic_id AS id_offer_topic,
    firestore_id AS id_firestore,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    comment,
    iteration,
    actor_role,
    proposed_rent_value,
    comment_mod AS mod_comment,
    proposed_rent_value_mod AS mod_proposed_rent_value,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_transact_raw.offer_topic_message_aud