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
),
analyzed_offers_rental_transact AS (
    SELECT
        oa.id AS id_offer,
        MIN(ts_rev) AS first_ts_revision
    FROM 
        datalake_rental_transact_clean.offer_aud AS oa
    JOIN 
        datalake_rental_transact_clean.rev_info AS ri
            ON oa.rev = ri.rev
    WHERE 
        oa.ts_created >= '2025-01-06' --Oficial start of rental_transact database
        AND oa.mod_status
        AND oa.status IN ('ACCEPTED', 'REJECTED')
    GROUP BY 1
),
negotiation_rental_transact AS (
  WITH offer_min_max_aud AS (
        SELECT
          o_aud.id AS id_offer,
          otma.actor_role,
          MAX(otma.rev) AS max_rev,
          MIN(otma.rev) AS min_rev
        FROM 
          datalake_rental_transact_clean.offer_aud AS o_aud
        JOIN
        datalake_rental_transact_clean.offer_topic_aud AS ota
          ON ota.id_offer = o_aud.id
        JOIN
            datalake_rental_transact_clean.offer_topic_message_aud AS otma
              ON otma.id_offer_topic = ota.id
        GROUP BY 1, 2
    )
    SELECT
        o.id AS id_offer,
        MIN(
            IF(
                offer_min_aud.actor_role = 'DEMAND'
                   AND offer_min_aud.min_rev IS NOT NULL,
                otma.proposed_rent_value,
                NULL
             )
        ) AS first_rent_offered_by_tenant,
        MIN(
            IF(
                offer_min_aud.actor_role = 'SUPPLY'
                    AND offer_min_aud.min_rev IS NOT NULL,
                otma.proposed_rent_value,
                NULL
            )
        ) AS first_rent_offered_by_owner,
        MAX(
            IF(
                offer_max_aud.actor_role = 'DEMAND'
                    AND offer_max_aud.max_rev IS NOT NULL,
                otma.proposed_rent_value,
                NULL
            )
        ) AS last_rent_offered_by_tenant,
        MAX(
            IF(
                offer_max_aud.actor_role = 'SUPPLY'
                    AND offer_max_aud.max_rev IS NOT NULL,
                otma.proposed_rent_value,
                NULL
            )
        ) AS last_rent_offered_by_owner
    FROM 
        datalake_rental_transact_clean.offer AS o
    JOIN
        datalake_rental_transact_clean.offer_topic_aud AS ota
          ON ota.id_offer = o.id
    JOIN
        datalake_rental_transact_clean.offer_topic_message_aud AS otma
          ON otma.id_offer_topic = ota.id
    LEFT JOIN 
        offer_min_max_aud AS offer_max_aud
            ON offer_max_aud.id_offer = ota.id_offer 
            AND offer_max_aud.max_rev = otma.rev
    LEFT JOIN 
        offer_min_max_aud AS offer_min_aud
            ON offer_min_aud.id_offer = ota.id_offer
            AND offer_min_aud.min_rev = otma.rev
    GROUP BY 1
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
    ri.introduction AS tenant_description,
    negotiation.first_rent_offered_by_tenant,
    negotiation.first_rent_offered_by_owner,
    negotiation.last_rent_offered_by_tenant,
    negotiation.last_rent_offered_by_owner,
    o.ts_created,
    o.ts_updated,
    o.ts_expiration,
    analyzed.first_ts_revision AS ts_analyzed,
    YEAR(o.ts_created) AS year,
    MONTH(o.ts_created) AS month,
    DAY(o.ts_created) AS day
FROM
    datalake_rental_transact_clean.offer AS o
LEFT JOIN
    datalake_rental_transact_clean.offer_topic AS ot
        ON o.id = ot.id_offer
        AND ot.type = 'PRICE'
LEFT JOIN
    topic_message AS tm
        ON tm.id_offer_topic = ot.id
JOIN
    datalake_ebdb_clean.house AS h
        ON o.id_house_external = h.id
LEFT JOIN
    datalake_rental_transact_clean.resident_info AS ri
        ON o.id_resident_info = ri.id
LEFT JOIN
    negotiation_rental_transact AS negotiation
        ON negotiation.id_offer = o.id
LEFT JOIN
    analyzed_offers_rental_transact AS analyzed
        ON analyzed.id_offer = o.id