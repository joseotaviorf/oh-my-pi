WITH autonomous_agent_info AS (
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
    WITH
    lbc AS (
        SELECT
            id_house,
            MAX(IF(business_context = 'SALE', status, NULL)) AS house_sale_status,
            MAX(IF(business_context = 'SALE', status_reason, NULL)) AS house_sale_status_reason,
            MAX(IF(business_context = 'RENT', status, NULL)) AS house_rent_status,
            MAX(IF(business_context = 'RENT', status_reason, NULL)) AS house_rent_status_reason
        FROM
            datalake_ebdb_listing.listing_business_context
        GROUP BY 1
    ),
    lrm AS (
        SELECT
            lbc.id_house,
            lrm.rental_administrator,
            FROM_UNIXTIME(CAST(ure.ts_revision AS BIGINT)/1000) AS ts_rental_administrator_start,
            LEAD(FROM_UNIXTIME(CAST(ure.ts_revision AS BIGINT)/1000)) OVER (PARTITION BY lbc.id_house ORDER BY lrm.rev) AS ts_rental_administrator_end
        FROM
            datalake_ebdb_clean.listing_rent_model_aud AS lrm
        JOIN
            datalake_ebdb_clean.listing_business_context AS lbc
                ON lbc.id = lrm.id_listing_business_context
        JOIN
            datalake_ebdb_clean.user_revision_entity AS ure
                ON ure.id = lrm.rev
    ),
    change_requests AS (
        SELECT
            rcr.id_house,
            rcr.ts_migrated AS ts_administration_ended,
            rcr.old_rental_administrator AS rental_administrator_origin
        FROM
            datalake_ebdb_clean.rental_administrator_change_request AS rcr
        WHERE
            rcr.old_rental_administrator = 'OWNER' 
            AND rcr.status = 'SUCCESS'
    )
    SELECT DISTINCT
        hl.id_house_listing AS sk_house_listing,
        h.id AS id_house,
        h.id % 892700000 AS short_id_house,
        h.country_code,
        hl.version,
        awk.first_key_location,
        CAST(hl.status AS STRING) AS status,
        hl.status_reason,
        hl.rent_type,
        awk.is_keys_with_agent_eligible,
        hl.ts_listing_version_start,
        hl.ts_listing_version_end,
        h.dt_first_publication AS ts_house_first_publication,
        h.ts_last_publication AS ts_house_last_publication,
        CASE
            WHEN hl.version = 1 THEN hl.ts_first_publication
            WHEN hl.version > 0 THEN hl.ts_listing_version_start
            ELSE NULL
        END AS ts_publication,
        hl.ts_last_unpublished,
        hl.rent,
        FIRST(lrm.rental_administrator) OVER (PARTITION BY hl.id_house_listing ORDER BY lrm.ts_rental_administrator_start DESC) AS rental_administrator,
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
        h.floor,
        h.bathrooms AS house_bathrooms,
        h.bedrooms AS house_bedrooms,
        h.suites AS house_suites,
        h.parking_slots AS house_garages,
        h.status AS house_status,
        lbc.house_rent_status,
        lbc.house_rent_status_reason,
        lbc.house_sale_status,
        lbc.house_sale_status_reason,
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
        h.partner_3p_supply,
        CASE
            WHEN h.is_sale_3p_supply THEN h.partner_3p_supply
        END AS partner_sale_3p_supply,
        CASE
            WHEN h.is_rent_3p_supply THEN h.partner_3p_supply
        END AS partner_rent_3p_supply,
        hl.listing_category,
        hl.is_last_version,
        hl.is_exclusive,
        hl.who_is_living,
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
        hl.is_for_rent,
        hl.is_for_sale,
        h.has_instant_offer_enabled,
        h.is_3p_supply,
        h.is_sale_3p_supply,
        h.is_rent_3p_supply,
        h.is_3p_supply_5a,
        h.is_3p_supply_bh,
        h.is_casa_mineira_migration,
        h.is_sale_primary_market,
        hl.is_extended_rental,
        hl.has_termination_canceled,
        IF(cr.id_house IS NOT NULL, TRUE, FALSE) AS is_brokerage_only_migrated,
        MAX(lrm.ts_rental_administrator_start) OVER (PARTITION BY hl.id_house_listing) AS ts_administrator_changed,
        hl.is_early_demand,
        hl.ts_early_demand_started
    FROM
        datalake_ebdb_listing.house AS h
    JOIN
        datalake_ebdb_listing.house_listing AS hl
            ON hl.id_house = h.id
    LEFT JOIN 
        lbc
            ON lbc.id_house = h.id
    LEFT JOIN 
        lrm
            ON lrm.id_house = lbc.id_house
                AND lrm.ts_rental_administrator_start <= COALESCE(hl.ts_listing_version_end, NOW())
                AND COALESCE(lrm.ts_rental_administrator_end, NOW()) >= hl.ts_listing_version_start
    LEFT JOIN
        change_requests AS cr
            ON cr.id_house = hl.id_house
                AND cr.ts_administration_ended BETWEEN hl.ts_listing_version_start AND COALESCE(hl.ts_listing_version_end, NOW())
    LEFT JOIN
        datalake_ebdb_listing.agents_with_keys AS awk
            ON hl.id_house_listing = awk.id_house_listing
)
SELECT -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
    hl.sk_house_listing,
    COALESCE(aa_info.sk_partner_agent, -1) AS sk_autonomous_agent,
    hl.id_house,
    hl.short_id_house,
    hl.country_code,
    CAST(hl.version AS SMALLINT) AS version,
    hlco.consultant_type,
    hlco.first_consultant_type,
    hl.first_key_location,
    hl.status,
    hl.status_reason,
    hl.rent_type,
    CAST(hl.rent AS DECIMAL(14, 2)) AS rent,
    IF(is_for_rent = TRUE, COALESCE(hl.rental_administrator, 'QUINTOANDAR'), NULL) AS rental_administrator,
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
    hl.floor,
    CAST(hl.house_bathrooms AS SMALLINT) AS house_bathrooms,
    CAST(hl.house_bedrooms AS SMALLINT) AS house_bedrooms,
    CAST(hl.house_suites AS SMALLINT) AS house_suites,
    CAST(hl.house_garages AS SMALLINT) AS house_garages,
    hl.house_status,
    hl.house_rent_status,
    hl.house_rent_status_reason,
    hl.house_sale_status,
    hl.house_sale_status_reason,
    hl.house_type,
    hl.house_entrance,
    hl.house_garage_type,
    CAST(hlf.administration_fee AS FLOAT) AS administration_fee,
    CAST(hl.house_total_value AS DECIMAL(14, 2)) AS house_total_value,
    CAST(hl.house_total_area AS DECIMAL(14, 2)) AS house_total_area,
    CAST(hl.house_construction_area AS DECIMAL(14, 2)) AS house_construction_area,
    hl.house_condo_type,
    hl.house_iptu_type,
    hl.registration_abandoned_reason,
    hl.house_unpublished_reason,
    hl.partner_3p_supply,
    hl.partner_sale_3p_supply,
    hl.partner_rent_3p_supply,
    hl.listing_category AS listing_category_start,
    hl.who_is_living,
    hl.key_type,
    hl.key_location,
    CAST(hl.house_predicted_price AS DECIMAL(14, 2)) AS house_predicted_price,
    b2b.b2b_type,
    CASE
      WHEN b2b.is_portability THEN 'portability'
      ELSE b2b.b2b_prime_type
    END AS b2b_prime_type,
    hl.last_originals_type,
    hl.last_iorent_type,
    CAST(hl.sale_price AS LONG) AS sale_price,
    hl.has_visit_restriction,
    hl.has_instant_offer_enabled,
    hl.is_house_furnished,
    hl.is_house_registration_verified,
    hl.is_keys_with_agent_eligible,
    hl.is_last_version,
    hl.is_exclusive,
    hl.is_extended_rental,
    hl.has_termination_canceled,
    hl.is_brokerage_only_migrated,
    b2b.is_b2b,
    COALESCE(aa_info.sk_partner_agent IS NOT NULL, FALSE) AS is_autonomous_agent,
    hl.is_originals_active,
    hl.is_iorent_active,
    hl.is_for_rent,
    hl.is_for_sale,
    hl.is_3p_supply,
    hl.is_sale_3p_supply,
    hl.is_rent_3p_supply,
    hl.is_3p_supply_5a,
    hl.is_3p_supply_bh,
    hl.is_casa_mineira_migration,
    hl.is_sale_primary_market,
    COALESCE(hl.is_early_demand, FALSE) AS is_early_demand,
    hlco.dt_consultant_started,
    hl.dt_last_exclusive_opted_in,
    hl.dt_last_exclusive_opted_out,
    hl.dt_last_originals_opted_in,
    hl.dt_last_originals_opted_out,
    hl.dt_last_iorent_opted_in,
    hl.dt_last_iorent_opted_out,
    hl.ts_early_demand_started,
    hlco.ts_consultant_deleted,
    IF(version > 0, hl.ts_listing_version_start, NULL) AS ts_listing_version_start,
    hl.ts_listing_version_end,
    hl.ts_publication,
    hl.ts_house_first_publication,
    hl.ts_house_last_publication,
    hl.ts_last_unpublished AS ts_last_de_publication,
    hl.ts_house_create,
    hl.ts_house_update,
    hl.ts_administrator_changed,
    NOW() AS ts_load
FROM
    house_listings AS hl
LEFT JOIN
    datalake_b2b.house_listing AS b2b
        ON b2b.id_house_listing = hl.sk_house_listing
LEFT JOIN
    autonomous_agent_info AS aa_info
        ON aa_info.sk_house_listing = hl.sk_house_listing
LEFT JOIN
    datalake_ebdb_listing.house_listing_fees AS hlf
        ON hl.sk_house_listing = hlf.id_house_listing
LEFT JOIN
    datalake_big_agent.house_rent_listing_consultant AS hlco
        ON hlco.id_house_listing = hl.sk_house_listing
        AND hlco.is_last_ciq_on_listing IS TRUE