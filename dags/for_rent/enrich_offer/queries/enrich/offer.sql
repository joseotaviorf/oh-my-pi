WITH 
analyzed_offers AS (
    SELECT
        oa.id_offer,
        min(ts_revision) AS first_ts_revision
    FROM 
        datalake_ebdb_clean.offer_aud AS oa
    JOIN 
        datalake_ebdb_user.user_revision_entity AS ure
            ON oa.rev = ure.id
    WHERE 
        oa.mod_status
        AND oa.status IN ('Aprovada', 'Rejeitada')
    GROUP BY 1
),
offer_negotiation AS (
    WITH 
    offer_min_max_aud AS (
        SELECT
            id_offer,
            turn,
            MAX(rev) AS max_rev,
            MIN(rev) AS min_rev
        FROM 
            datalake_ebdb_clean.offer_aud AS oa
        GROUP BY 1, 2
    )
    SELECT
        o_aud.id_offer,
        MIN(
            IF(
                offer_min_aud.turn = 'Owner'
                   AND offer_min_aud.min_rev IS NOT NULL,
                o_aud.rent,
                NULL
             )
        ) AS first_rent_offered_by_tenant,
        MIN(
            IF(
                offer_min_aud.turn = 'Tenant'
                    AND offer_min_aud.min_rev IS NOT NULL,
                o_aud.rent,
                NULL
            )
        ) AS first_rent_offered_by_owner,
        MAX(
            IF(
                offer_max_aud.turn = 'Owner'
                    AND offer_max_aud.max_rev IS NOT NULL,
                o_aud.rent,
                null
            )
        ) AS last_rent_offered_by_tenant,
        MAX(
            IF(
                offer_max_aud.turn = 'Tenant'
                    AND offer_max_aud.max_rev IS NOT NULL,
                o_aud.rent,
                NULL
            )
        ) AS last_rent_offered_by_owner
    FROM 
        datalake_ebdb_clean.offer_aud AS o_aud
    LEFT JOIN 
        offer_min_max_aud AS offer_max_aud
            ON offer_max_aud.id_offer = o_aud.id_offer
            AND offer_max_aud.max_rev = o_aud.rev
    LEFT JOIN 
        offer_min_max_aud AS offer_min_aud
            ON offer_min_aud.id_offer = o_aud.id_offer
            AND offer_min_aud.min_rev = o_aud.rev
    GROUP BY 1
),
firestore_offers AS (
    WITH 
    offer_firestore AS (
        SELECT
            offer.id as id_offer,
            MAX(COALESCE(offer.id_godfather, g_offer.id))
                OVER (PARTITION BY offer.id_firestore) AS id_offer_godfather,
            offer.id_firestore
        FROM 
            datalake_ebdb_clean.offer
        LEFT JOIN 
            datalake_godfather_clean.offer g_offer
                ON offer.id_firestore = g_offer.id_firestore
                AND offer.id_godfather IS NULL
    ),
    instant_offer_firestore AS (
        SELECT DISTINCT
            id_firestore,
            GET_JSON_OBJECT(resident, '$.people') AS number_of_tenants,
            GET_JSON_OBJECT(resident, '$.kids') AS number_of_kids,
            GET_JSON_OBJECT(tenant_intent, '$.rentalReason') AS rental_reason,
            GET_JSON_OBJECT(tenant_intent, '$.urgency') AS rental_urgency,
            GET_JSON_OBJECT(resident, '$.description') AS tenant_description,
            GET_JSON_OBJECT(resident, '$.petsInfo') AS tenant_pets_info,
            GET_JSON_OBJECT(resident, '$.members') AS tenant_type,
            type,
            GET_JSON_OBJECT(resident, '$.pets') AS has_pets,
            is_instant_offer,
            ts_email_sent_to_owner,
            ts_first_sent,
            ts_last_sent
        FROM 
            datalake_firestore.rent_offer AS fo
        WHERE 
            status NOT IN ('Draft','DismissedDraft')
    )
    SELECT DISTINCT
        o_firestore.id_offer,
        o_firestore.id_firestore,
        bo_godfather.id,
        io_firestore.number_of_tenants,
        io_firestore.number_of_kids,
        io_firestore.rental_reason,
        io_firestore.rental_urgency,
        io_firestore.tenant_description,
        io_firestore.tenant_pets_info,
        io_firestore.tenant_type,
        io_firestore.type,
        io_firestore.has_pets,
        io_firestore.is_instant_offer,
        io_firestore.ts_email_sent_to_owner,
        COALESCE(bo_godfather.ts_first_sent, io_firestore.ts_first_sent) AS ts_first_sent,
        COALESCE(bo_godfather.ts_last_sent, io_firestore.ts_last_sent) AS ts_last_sent
    FROM 
        offer_firestore AS o_firestore
    LEFT JOIN 
        datalake_godfather_clean.offer AS bo_godfather
            ON bo_godfather.id = o_firestore.id_offer_godfather
    LEFT JOIN 
        instant_offer_firestore AS io_firestore
            ON o_firestore.id_firestore = io_firestore.id_firestore
),
rental_transact_io AS (
    SELECT 
        o.id AS id_offer_rental_transact
    FROM 
        datalake_rental_transact_clean.offer AS o 
    JOIN 
        datalake_rental_transact_clean.event_log AS el 
            ON el.id_rent_flow = o.id
    WHERE 
        el.type = 'NEGOTIATION_OFFER_ACCEPTED'
        AND el.actor_role = 'SYSTEM'
)
SELECT DISTINCT
    UUID() AS id_offer_history,
    offer.id,
    NULL AS id_offer_rental_transact,
    (offer.id * 100) + 2 AS id_offer_context,
    offer.id_firestore,
    -- TODO [ODS] bug in Product attaching the same firestore id to different godfather entries
    MAX(COALESCE(offer.id_godfather, firestore.id)) OVER (PARTITION BY offer.id_firestore) AS id_godfather,
    hl.id_country,
    offer.id_client,
    NULL AS id_owner,
    client.uuid_person AS uuid_person_tenant,
    NULL AS uuid_person_owner,
    offer.id_house,
    offer.id_rent_flow,
    hl.country_code,
    offer.original_condo,
    offer.original_home_insurance,
    offer.original_iptu,
    offer.original_rent,
    offer.status,
    offer.turn,
    offer.rejection_reason,
    offer.iteration,
    COALESCE(firestore.type, bus_offer.type, offer.type) AS type,
    offer.rent AS last_offered_rent,
    negotiation.first_rent_offered_by_tenant,
    negotiation.first_rent_offered_by_owner,
    negotiation.last_rent_offered_by_tenant,
    negotiation.last_rent_offered_by_owner,
    firestore.number_of_tenants,
    firestore.number_of_kids,
    firestore.rental_reason,
    firestore.rental_urgency,
    firestore.tenant_description,
    firestore.tenant_pets_info,
    firestore.tenant_type,
    firestore.has_pets,
    COALESCE(firestore.is_instant_offer, false) AS is_instant_offer,
    COALESCE(bus_offer.ts_last_sent, firestore.ts_last_sent) IS NOT NULL AS is_offer_submitted,
    firestore.ts_email_sent_to_owner,
    offer.ts_expired,
    analyzed.first_ts_revision AS ts_analyzed,
    COALESCE(bus_offer.ts_first_sent, firestore.ts_first_sent) AS ts_first_sent,
    COALESCE(bus_offer.ts_last_sent, firestore.ts_last_sent) AS ts_last_sent,
    offer.ts_created,
    offer.ts_updated
FROM 
    datalake_ebdb_clean.offer AS offer
LEFT JOIN 
    analyzed_offers AS analyzed
        ON analyzed.id_offer = offer.id
LEFT JOIN 
    datalake_godfather_clean.offer AS bus_offer
        ON offer.id_godfather = bus_offer.id
        AND offer.id_godfather IS NOT NULL
LEFT JOIN 
    firestore_offers AS firestore
        ON offer.id = firestore.id_offer
LEFT JOIN 
    offer_negotiation AS negotiation
        ON negotiation.id_offer = offer.id
JOIN
    datalake_ebdb_country.house AS hl
        ON hl.id_house = offer.id_house
LEFT JOIN
    datalake_ebdb_clean.user AS client
        ON client.id = offer.id_client
WHERE
    COALESCE(bus_offer.ts_first_sent, firestore.ts_first_sent) < '2025-01-13'

UNION

SELECT
    UUID() AS id_offer_history, 
    firestore.id_offer AS id, --Temporarily bring the id_offer from EBDB to prevent major impacts on the pipeline and give time to adjustments
    offer.id_offer AS id_offer_rental_transact,
    (firestore.id_offer * 100) + 2 AS id_offer_context,
    offer.id_firestore AS id_firestore,
    NULL AS id_godfather,
    hl.id_country,
    tenant.id AS id_client,
    owner.id AS id_owner,
    tenant.uuid_person AS uuid_person_tenant,
    owner.uuid_person AS uuid_person_owner,
    offer.id_house,
    ebdb_offer.id_rent_flow AS id_rent_flow, --Temporarily bring the id_rent_flow from EBDB to prevent major impacts on the pipeline and give time to adjustments
    hl.country_code,
    offer.original_condo,
    offer.original_home_insurance,
    offer.original_iptu,
    offer.original_rent,
    offer.status,
    offer.turn,
    offer.rejection_reason,
    offer.iteration,
    offer.type,
    offer.rent AS last_offered_rent,
    offer.first_rent_offered_by_tenant,
    offer.first_rent_offered_by_owner,
    offer.last_rent_offered_by_tenant,
    offer.last_rent_offered_by_owner,
    number_of_cohabitants AS number_of_tenants,
    NULL AS number_of_kids,
    NULL AS rental_reason,
    NULL AS rental_urgency,
    offer.tenant_description,
    NULL AS tenant_pets_info,
    NULL AS tenant_type,
    NULL AS has_pets,
    (io.id_offer_rental_transact IS NOT NULL) AS is_instant_offer,
    TRUE AS is_offer_submitted,
    offer.ts_created AS ts_email_sent_to_owner,
    offer.ts_expiration AS ts_expired,
    offer.ts_analyzed,
    offer.ts_created AS ts_first_sent,
    offer.ts_updated AS ts_last_sent,
    offer.ts_created,
    offer.ts_updated
FROM 
    datalake_rental_transact.offer AS offer
JOIN
    datalake_ebdb_country.house AS hl
        ON hl.id_house = offer.id_house
JOIN 
    firestore_offers AS firestore
        ON offer.id_firestore = firestore.id_firestore
LEFT JOIN
    datalake_ebdb_clean.offer AS ebdb_offer
        ON ebdb_offer.id_firestore = offer.id_firestore
LEFT JOIN
    datalake_ebdb_clean.user AS tenant
        ON tenant.uuid_person = offer.id_tenant
LEFT JOIN
    datalake_ebdb_clean.user AS owner
        ON owner.uuid_person = offer.id_owner
LEFT JOIN
    rental_transact_io AS io
        ON io.id_offer_rental_transact = offer.id_offer
WHERE 
    offer.ts_created >= '2025-01-13'