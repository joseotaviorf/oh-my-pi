WITH b2b_info AS (
    SELECT DISTINCT
        h.id AS id_house,
        hl.id_house_listing,
        -- TODO [ODS]: centralize rules like these ones
        COALESCE(
            COALESCE(lo.affiliate_type, l.affiliate_type) = 'B2BPartner'
                OR (partner_agent.id IS NOT NULL AND partner.type = 'PRIME'),
            FALSE
            )
        AS is_b2b,
        CASE
          WHEN COALESCE(lo.affiliate_type, l.affiliate_type) = 'B2BPartner'
            THEN 'online'
          WHEN (partner_agent.id IS NOT NULL AND partner.type = 'PRIME')
            THEN 'prime'
        END AS b2b_type,
        CASE
            WHEN
                -- because a lead can have both 'affiliate_type' = 'B2BPartner' AND 'partner_agent.id' not null AND we need to
                -- prioritize the first type (online), the following check must be done
                partner_agent.id IS NOT NULL
                AND partner.type = 'PRIME'
                AND COALESCE(lo.affiliate_type, l.affiliate_type, '') != 'B2BPartner'
            THEN
              CASE
                WHEN pj.id IS NULL AND h.dt_first_publication IS NOT NULL
                  THEN 'advanced_negotiation'
                WHEN h.id_external IS NULL OR h.id_external RLIKE '^([a-zA-Z0-9]+-){{4}}[a-zA-Z0-9]+$'
                  THEN 'standard'
                WHEN h.id_external IS NOT NULL
                  THEN 'batch'
              END
        END AS b2b_prime_type
    FROM datalake_ebdb_clean.house h
    LEFT JOIN datalake_ebdb_clean.conversion_lead cl
        ON cl.id_house = h.id
    LEFT JOIN datalake_ebdb_clean.lead l
        ON l.id = cl.id_converted_lead
    LEFT JOIN datalake_lead.reprocessed_lead rl
        ON rl.id = l.id
    LEFT JOIN datalake_lead.lead lo
        ON lo.id = rl.id_origin_lead
    LEFT JOIN datalake_ebdb_clean.partner_agent partner_agent
        ON partner_agent.id_user = h.id_user
    LEFT JOIN datalake_ebdb_clean.partner partner
        ON partner.id = partner_agent.id_partner
    LEFT JOIN datalake_ebdb_listing.house_listing hl
        ON h.id = hl.id_house
    LEFT JOIN datalake_ebdb_clean.photographer_job pj
        ON pj.id_house = h.id
    AND pj.ts_created BETWEEN hl.ts_listing_version_start AND hl.ts_listing_version_end
),
house_portability AS (
    SELECT
        hl.id_house_listing
    FROM datalake_ebdb_listing.house_listing hl
    JOIN datalake_ebdb_clean.house h
        ON h.id = hl.id_house
    JOIN datalake_ebdb_clean.portability por
        ON por.id_house = hl.id_house AND por.owner_type = 'B2B'
    WHERE por.ts_created BETWEEN COALESCE(hl.ts_listing_version_start, '1900-01-01 00:00:00') AND COALESCE(hl.ts_listing_version_end, now())
),
autonomous_agent_info AS (
    SELECT
        h.id AS id_house,
        hl.id_house_listing AS sk_house_listing,
        partner_agent.id_user AS sk_partner_agent,
        partner_agent.id_partner AS sk_partner
    FROM datalake_ebdb_clean.partner_agent partner_agent
    JOIN datalake_ebdb_clean.partner partner
        ON partner_agent.id_partner = partner.id
    JOIN datalake_ebdb_clean.house h
        ON partner_agent.id_user = h.id_user_registrant
    LEFT JOIN datalake_ebdb_listing.house_listing hl
        ON h.id = hl.id_house
    LEFT JOIN datalake_ebdb_listing.listing_business_context lbc
        ON lbc.id_house = h.id
    WHERE
        lbc.business_context <> 'SALE'
        AND partner.type = 'AUTONOMOUS_AGENT'
        AND partner.id <> '257' -- Test User
        AND h.dt_creation >= partner_agent.ts_created --This rule might change WHEN we start to consider migration
        AND h.id_external IS NOT NULL --This rule might change WHEN we start to consider migration
),
house_listings AS (
    WITH lbc AS (
        SELECT
           id_house,
           CAST(MAX(CAST((business_context = 'SALE') AS INTEGER)) AS BOOLEAN) AS is_for_sale,
           CAST(MAX(CAST((business_context = 'RENT') AS INTEGER)) AS BOOLEAN) AS is_for_rent
        FROM datalake_ebdb_listing.listing_business_context
        GROUP BY 1
    )
    SELECT
        hl.id_house_listing AS sk_house_listing,
        h.id AS id_house,
        h.id % 892700000 AS short_id_house,
        hl.version,
        CAST(hl.status AS STRING) AS status,
        hl.ts_listing_version_start,
        hl.ts_listing_version_end,
        h.dt_first_publication AS ts_house_first_publication,
        h.ts_last_publication AS ts_house_last_publication,
        CAST(hl.ts_listing_version_start AS DATE) AS ts_publication,
        hl.ts_last_unpublished, -- TODO ts_last_unpublished CHECK WITH ts_last_de_publication
        hl.rent,
        h.rent AS house_rent,
        h.neighborhood AS house_neighborhood,
        h.zipcode AS house_zipcode,
        h.city AS house_city,
        h.complement AS house_complement,
        h.condo AS house_condo,
        h.has_elevator AS house_elevator,
        h.address AS house_address,
        h.iptu AS house_iptu,
        h.lat AS house_lat,
        h.lng AS house_lng,
        h.is_furnished AS is_house_furnished,
        h.number AS house_number,
        h.bathrooms AS house_bathrooms,
        h.bedrooms AS house_bedrooms,
        h.suites AS house_suites,
        h.parking_slots AS house_garages,
        h.status AS house_status,
        h.type AS house_type,
        h.doorman_type AS house_entrance,
        h.parking_slot_type AS house_garage_type,
        h.is_verified AS is_house_registration_verified,
        h.total_value AS house_total_value,
        h.total_area AS house_total_area,
        h.land_area AS house_construction_area,
        h.condo_type AS house_condo_type,
        h.iptu_type AS house_iptu_type,
        h.dt_creation AS ts_house_create,
        h.ts_updated AS ts_house_update,
        h.registration_abandoned_reason AS registration_abandoned_reason,
        h.unpublished_reason AS house_unpublished_reason,
        hl.listing_category,
        hl.is_last_version,
        hl.is_exclusive,
        h.occupant_type AS who_is_living,
        h.key_type,
        h.key_location,
        COALESCE(h.visit_restriction = 'Restriction', FALSE) AS has_visit_restriction,
        h.predicted_price AS house_predicted_price,
        hl.dt_last_exclusive_opted_in,
        hl.dt_last_exclusive_opted_out,
        hl.is_originals_active,
        hl.last_originals_type,
        hl.dt_last_originals_opted_in,
        hl.dt_last_originals_opted_out,
        hl.is_iorent_active,
        hl.last_iorent_type,
        hl.dt_last_iorent_opted_in,
        hl.dt_last_iorent_opted_out,
        h.sale_price,
        CASE
            WHEN lbc.id_house IS NULL
                THEN TRUE -- When house is not in listing_business_context, it is for rent
            ELSE COALESCE(lbc.is_for_rent, FALSE)
        END AS is_for_rent,
        COALESCE(lbc.is_for_sale, FALSE) AS is_for_sale,
        h.has_instant_offer_enabled
    FROM datalake_ebdb_listing.house h
    JOIN datalake_ebdb_listing.house_listing hl
        ON hl.id_house = h.id
    LEFT JOIN lbc
        ON lbc.id_house = h.id
)
SELECT -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
    hl.sk_house_listing,
    COALESCE(aa_info.sk_partner_agent, -1) AS sk_autonomous_agent,
    hl.id_house,
    hl.short_id_house,
    CAST(hl.version AS SMALLINT) AS version,
    hl.status,
    CAST(hl.rent AS DECIMAL(14, 2)) AS rent,
    CAST(hl.house_rent AS DECIMAL(14, 2)) AS house_rent,
    NULLIF(hl.house_neighborhood, '') AS house_neighborhood,
    hl.house_zipcode,
    hl.house_city,
    NULLIF(hl.house_complement, '') AS house_complement,
    CAST(hl.house_condo AS DECIMAL(14, 2)) AS house_condo,
    CAST(hl.house_elevator AS SMALLINT) AS house_elevator,
    hl.house_address,
    CAST(hl.house_iptu AS DECIMAL(14, 2)) AS house_iptu,
    CAST(hl.house_lat AS DECIMAL(14, 7)) AS house_lat,
    CAST(hl.house_lng AS DECIMAL(14, 7)) AS house_lng,
    hl.house_number,
    CAST(hl.house_bathrooms AS SMALLINT) AS house_bathrooms,
    CAST(hl.house_bedrooms AS SMALLINT) AS house_bedrooms,
    CAST(hl.house_suites AS SMALLINT) AS house_suites,
    CAST(hl.house_garages AS SMALLINT) AS house_garages,
    hl.house_status,
    hl.house_type,
    hl.house_entrance,
    hl.house_garage_type,
    CAST(hl.house_total_value AS DECIMAL(14, 2)) AS house_total_value,
    CAST(hl.house_total_area AS DECIMAL(14, 2)) AS house_total_area,
    CAST(hl.house_construction_area AS DECIMAL(14, 2)) AS house_construction_area,
    hl.house_condo_type,
    hl.house_iptu_type,
    hl.registration_abandoned_reason,
    hl.house_unpublished_reason,
    hl.listing_category as listing_category_start,
    hl.who_is_living,
    hl.key_type,
    hl.key_location,
    CAST(hl.house_predicted_price AS DECIMAL(14, 2)) AS house_predicted_price,
    bi.b2b_type,
    CASE
      WHEN hp.id_house_listing IS NOT NULL THEN 'portability'
      ELSE bi.b2b_prime_type
    END AS b2b_prime_type,
    hl.last_originals_type,
    hl.last_iorent_type,
    CAST(hl.sale_price AS LONG) AS sale_price,
    hl.has_visit_restriction,
    hl.has_instant_offer_enabled,
    hl.is_house_furnished,
    hl.is_house_registration_verified,
    hl.is_last_version,
    hl.is_exclusive,
    (bi.is_b2b OR hp.id_house_listing IS NOT NULL) AS is_b2b,
    COALESCE(aa_info.sk_partner_agent IS NOT NULL, FALSE) AS is_autonomous_agent,
    hl.is_originals_active,
    hl.is_iorent_active,
    hl.is_for_rent,
    hl.is_for_sale,
    hl.dt_last_exclusive_opted_in,
    hl.dt_last_exclusive_opted_out,
    hl.dt_last_originals_opted_in,
    hl.dt_last_originals_opted_out,
    hl.dt_last_iorent_opted_in,
    hl.dt_last_iorent_opted_out,
    hl.ts_listing_version_start,
    hl.ts_listing_version_end,
    CAST(hl.ts_publication AS TIMESTAMP) AS ts_publication,
    hl.ts_house_first_publication,
    hl.ts_house_last_publication,
    hl.ts_last_unpublished as ts_last_de_publication,
    hl.ts_house_create,
    hl.ts_house_update,
    NOW() AS ts_load
FROM house_listings hl
LEFT JOIN b2b_info bi
    ON bi.id_house_listing = hl.sk_house_listing
LEFT JOIN house_portability hp
    ON hp.id_house_listing = hl.sk_house_listing
LEFT JOIN autonomous_agent_info aa_info
	ON aa_info.sk_house_listing = hl.sk_house_listing