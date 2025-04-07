SELECT
    MONOTONICALLY_INCREASING_ID() AS pk_offer_negotiations,
    o.id_offer AS sk_offer,
    ot.id AS sk_offer_topic,
    otm.id_topic_message AS sk_offer_topic_message,
    o.id_tenant AS sk_client,
    o.id_owner AS sk_owner,
    o.id_house AS sk_house,
    hl.id_house_listing AS sk_house_listing,
    IF(otm.iteration IS NULL OR otm.max_topic_iteration = otm.iteration, TRUE, FALSE) AS is_last_topic_iteration
FROM
    datalake_rental_transact.offer AS o
LEFT JOIN
    datalake_rental_transact_clean.offer_topic AS ot
        ON ot.id_offer = o.id_offer
LEFT JOIN
    datalake_rental_transact.offer_topic_message AS otm
        ON otm.id_offer_topic = ot.id
JOIN
    datalake_ebdb_listing.house_listing AS hl
        ON hl.id_house = o.id_house
            AND COALESCE(o.ts_created, '1900-01-01') BETWEEN
                COALESCE(hl.ts_listing_version_start, '1900-01-01')
                AND COALESCE(hl.ts_listing_version_end, NOW())