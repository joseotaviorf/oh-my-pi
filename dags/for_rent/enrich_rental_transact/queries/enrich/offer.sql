WITH
topic_message AS (
    SELECT
        otm.id,
        otm.id_offer_topic,
        otm.proposed_rent_value,
        otm.iteration
    FROM
        datalake_rental_transact_clean.offer_topic_message AS otm
    JOIN
        datalake_rental_transact_clean.offer_topic AS ot
            ON otm.id_offer_topic = ot.id
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY ot.id_offer ORDER BY otm.iteration DESC) = 1
)
SELECT
    o.id AS id_offer,
    tm.id_offer_topic,
    o.id_firestore_offer AS id_firestore,
    o.id_tenant_external AS id_tenant,
    o.id_owner_external as id_owner,
    o.id_house_external AS id_house,
    h.condo AS original_condo,
    h.insurance_value AS original_home_insurance,
    h.iptu AS original_iptu,
    o.original_rent_value AS original_rent,
    tm.proposed_rent_value as rent,
    o.status,
    o.turn,
    o.iteration,
    o.rejection_reason,
    o.type,
    ri.number_of_cohabitants,
    o.ts_created,
    o.ts_updated,
    o.ts_expiration,
    YEAR(o.ts_created) AS year,
    MONTH(o.ts_created) AS month,
    DAY(o.ts_created) AS day
FROM
    datalake_rental_transact_clean.offer AS o
JOIN
    datalake_rental_transact_clean.offer_topic AS ot
        ON o.id = ot.id_offer
JOIN
    topic_message AS tm
        ON tm.id_offer_topic = ot.id
JOIN
    datalake_ebdb_clean.house AS h
        ON o.id_house_external = h.id
JOIN
    datalake_rental_transact_clean.resident_info AS ri
        ON o.id_resident_info = ri.id
