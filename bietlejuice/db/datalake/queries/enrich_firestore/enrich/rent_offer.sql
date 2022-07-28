WITH last_update AS (
SELECT
    id,
    ts_updated AS ts_updated_message,
    ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) AS ranking_last_updated_message
FROM datalake_firestore_clean.rent_offer
)
SELECT
    roa.id AS id_firestore,
    BIGINT(GET_JSON_OBJECT(roa.updated_message, '$.house.id')) AS id_house,
    BIGINT(GET_JSON_OBJECT(roa.updated_message, '$.ownerId')) AS id_owner,
    BIGINT(GET_JSON_OBJECT(roa.updated_message, '$.partnerId')) AS id_partner,
    BIGINT(GET_JSON_OBJECT(roa.updated_message, '$.tenantId')) AS id_tenant,
    GET_JSON_OBJECT(roa.updated_message, '$.ownerIdString') AS id_owner_string,
    GET_JSON_OBJECT(roa.updated_message, '$.tenantIdString') AS id_tenant_string,
    GET_JSON_OBJECT(roa.updated_message, '$.code') AS code,
    GET_JSON_OBJECT(roa.updated_message, '$.comentario') AS comment,
    GET_JSON_OBJECT(roa.updated_message, '$.house') AS house,
    GET_JSON_OBJECT(roa.updated_message, '$.iteration') AS iteration,
    GET_JSON_OBJECT(roa.updated_message, '$.lastProposedRent') AS last_proposed_rent,
    GET_JSON_OBJECT(roa.updated_message, '$.lastProposedRentDraft') AS last_proposed_rent_draft,
    GET_JSON_OBJECT(roa.updated_message, '$.originOffer') AS origin_offer,
    GET_JSON_OBJECT(roa.updated_message, '$.originalRent') AS original_rent,
    GET_JSON_OBJECT(roa.updated_message, '$.originalTotal') AS original_total,
    GET_JSON_OBJECT(roa.updated_message, '$.rejectionReason') AS rejection_reason,
    GET_JSON_OBJECT(roa.updated_message, '$.rejectionReasonDescription') AS rejection_reason_description,
    GET_JSON_OBJECT(roa.updated_message, '$.resident') AS resident,
    GET_JSON_OBJECT(roa.updated_message, '$.status') AS status,
    GET_JSON_OBJECT(roa.updated_message, '$.turn') AS turn,
    GET_JSON_OBJECT(roa.updated_message, '$.type') AS type,
    GET_JSON_OBJECT(roa.updated_message, '$.tenantIntent') AS tenant_intent,
    GET_JSON_OBJECT(roa.updated_message, '$.tenantServiceFee') AS tenant_service_fee,
    BOOLEAN(GET_JSON_OBJECT(roa.updated_message, '$.hasDraftTopics')) AS has_draft_topics,
    BOOLEAN(GET_JSON_OBJECT(roa.updated_message, '$.instantOffer')) AS is_instant_offer,
    BOOLEAN(GET_JSON_OBJECT(roa.updated_message, '$.visualized')) AS is_visualized,
    TIMESTAMP(BIGINT(COALESCE(GET_JSON_OBJECT(roa.updated_message, '$.firstSentAt._seconds'), GET_JSON_OBJECT(roa.updated_message, '$.firstSentAt[*]._seconds')))) AS ts_first_sent,
    TIMESTAMP(BIGINT(COALESCE(GET_JSON_OBJECT(roa.updated_message, '$.lastSentDate._seconds'), GET_JSON_OBJECT(roa.updated_message, '$.lastSentDate[*]._seconds')))) AS ts_last_sent,
    TIMESTAMP(BIGINT(COALESCE(GET_JSON_OBJECT(roa.updated_message, '$.deadline._seconds'), GET_JSON_OBJECT(roa.updated_message, '$.deadline[*]._seconds')))) AS ts_deadline,
    TIMESTAMP(BIGINT(COALESCE(GET_JSON_OBJECT(roa.updated_message, '$.visualizedAt._seconds'), GET_JSON_OBJECT(roa.updated_message, '$.visualizedAt[*]._seconds')))) AS ts_visualized,
    TIMESTAMP(BIGINT(COALESCE(GET_JSON_OBJECT(roa.updated_message, '$.createdDate._seconds'), GET_JSON_OBJECT(roa.updated_message, '$.createdDate[*]._seconds')))) AS ts_created,
    TIMESTAMP(BIGINT(COALESCE(GET_JSON_OBJECT(roa.updated_message, '$.updated._seconds'), GET_JSON_OBJECT(roa.updated_message, '$.updated[*]._seconds')))) AS ts_updated,
    roa.ts_updated AS ts_updated_message,
    NOW() AS ts_load
FROM
  datalake_firestore_clean.rent_offer AS roa
INNER JOIN last_update lup
    ON roa.id = lup.id
    AND roa.ts_updated = lup.ts_updated_message
    AND lup.ranking_last_updated_message = 1
