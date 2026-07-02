WITH house_listing AS (
    SELECT
        hl.id_house,
        hl.id_contract,
        hl.id_house_listing,
        c.id_owner,
        hl.status AS listing_status,
        c.status AS contract_status,
        LEAD(hl.id_house_listing) OVER(PARTITION BY hl.id_house ORDER BY hl.ts_listing_version_start) IS NOT NULL AS has_republication,
        COALESCE(hl.status = 'OPTED_OUT' OR (hl.status = 'UNPUBLISHED' AND hl.status_reason != 'RENTED'), FALSE) AS is_house_inactive,
        IF(
            hl.ts_contract_signed IS NOT NULL,
            FIRST_VALUE(hl.id_house_listing) OVER(
                PARTITION BY hl.id_house, hl.ts_contract_signed IS NOT NULL 
                ORDER BY hl.ts_contract_signed
            ) = hl.id_house_listing,
            FALSE
        ) AS is_first_contract_signed,
        IF(
            hl.ts_contract_signed IS NOT NULL,
            FIRST_VALUE(hl.id_house_listing) OVER(
                PARTITION BY hl.id_house, hl.ts_contract_signed IS NOT NULL 
                ORDER BY hl.ts_contract_signed DESC
            ) = hl.id_house_listing,
            FALSE
        ) AS is_last_contract_signed,
        hl.is_last_version,
        hl.listing_category,
        hl.ts_publicated,
        hl.ts_listing_version_start,
        hl.ts_listing_version_end,
        hl.ts_contract_signed,
        LEAD(hl.ts_contract_signed) IGNORE NULLS OVER (
            PARTITION BY hl.id_house
            ORDER BY hl.version
        ) AS ts_next_contract_signed,
        LAG(hl.ts_contract_signed) IGNORE NULLS OVER (
            PARTITION BY hl.id_house
            ORDER BY hl.version
        ) AS ts_previous_contract_signed,
        c.dt_termination
    FROM
        datalake_ebdb_listing.house_listing AS hl
    LEFT JOIN
        core_contract.contract AS c
            ON hl.id_house = c.id_house
            AND hl.id_contract = c.id_contract
),
house_consultant_history AS (
    SELECT
        hch.id_house,
        hch.id_enrollment,
        hch.id_partner,
        hch.id_internal_agent,
        hch.id_user,
        hch.consultant_type,
        MIN(ts_agency_created) AS ts_house_registration
    FROM
        datalake_big_agent.house_consultant_history AS hch
    GROUP BY ALL
),
house_city_clean AS (
    SELECT
        id_house,
        TRIM(
            REGEXP_REPLACE(
                REGEXP_EXTRACT(
                    TRIM(LOWER(h.city)),
                    '^([^,/-]+)',
                    1
                ),
                '[^a-z ]',
                ''
            )
        ) AS city_name,
        TRANSLATE(
            REGEXP_REPLACE(
                TRIM(
                    REGEXP_REPLACE(
                        REGEXP_EXTRACT(
                            TRIM(LOWER(h.city)),
                            '^([^,/-]+)',
                            1
                        ),
                        '[^a-z ]',
                        ''
                    )
                ),
                '\\s+',
                ''
            ),
            'áàâãäéèêëíìîïóòôõöúùûüç',
            'aaaaaeeeeiiiiooooouuuuc'
        )  AS city_name_clean
    FROM
        core_house.house AS h
),
city_group(
    SELECT
        LOWER(city_name) AS city_name,
        TRANSLATE(
            REGEXP_REPLACE(TRIM(LOWER(r.city_name)), '\\s+', ''),
            'áàâãäéèêëíìîïóòôõöúùûüç',
            'aaaaaeeeeiiiiooooouuuuc'
        ) AS city_name_clean,
        LOWER(city_group) AS city_group,
        ROW_NUMBER() OVER(PARTITION BY city_name ORDER BY IF(city_group IS NOT NULL, 1, 0) DESC, ts_updated DESC) = 1 AS is_last_updated
    FROM
        datalake_region.region AS r
),
house_city_group AS (
    SELECT
        h.id_house,
        COALESCE(cg.city_name, cg2.city_name, cg3.city_name, h.city_name) AS city_name,
        COALESCE(cg.city_group, cg2.city_group, cg3.city_group) AS city_group,
        ROW_NUMBER() OVER (
            PARTITION BY h.id_house
            ORDER BY
                IF(cg.city_name IS NOT NULL, 0, 1),
                LEVENSHTEIN(h.city_name_clean, COALESCE(cg2.city_name_clean, cg3.city_name_clean))
        ) = 1 AS is_matched
    FROM
        house_city_clean AS h
    LEFT JOIN
        city_group AS cg
            ON h.city_name_clean = cg.city_name_clean
            AND cg.is_last_updated IS TRUE
    LEFT JOIN
        city_group AS cg2
            ON LEVENSHTEIN(h.city_name_clean, cg2.city_name_clean) <= 2
            AND cg2.is_last_updated IS TRUE
    LEFT JOIN
        city_group AS cg3
            ON STARTSWITH(h.city_name_clean, cg3.city_name_clean)
            AND cg3.is_last_updated IS TRUE
),
supply_source_rent AS (
    SELECT DISTINCT
        id_house,
        IF(company_report_origin = "CIQ - Operations", "CIQ", company_report_origin) AS supply_source
    FROM
        datalake_ciq.ciq_supply_events_tracking
    WHERE
        business_context = 'RENT'
        AND id_funnel_step = 6
)
SELECT
    XXHASH64(
        h.id_house,
        hl.id_house_listing,
        hch.id_partner,
        hch.id_user,
        lbc.business_context,
        hch.consultant_type
    ) AS id_listing_purchase,
    h.id_house,
    hch.id_partner,
    hl.id_house_listing,
    hl.id_contract,
    h.id_owner,
    hch.id_user AS id_ciq_user,
    hch.id_internal_agent,
    hch.id_enrollment,
    ae.id AS id_accounting_entry,
    ld.id_address_parsed_short AS id_address_parsed_duplicity,
    ahd.id_duplicity AS id_atlas_duplicity,
    ld.address_full AS address,
    ld.first_listing_order AS parsed_first_listing_order,
    hcg.city_name,
    hcg.city_group,
    ssr.supply_source,
    lbc.business_context,
    hch.consultant_type,
    COALESCE(hl.listing_status, lbc.status) AS listing_status,
    hl.listing_category,
    hl.contract_status,
    CASE
        WHEN hl.contract_status = 'Cancelado'	THEN 'cancelled'
        WHEN ae.id IS NOT NULL THEN 'paid'
        WHEN hl.ts_contract_signed IS NULL THEN 'not-eligible'
        ELSE 'pending'
    END AS payment_status,
    CASE
        WHEN lbc.business_context <> 'RENT' THEN 'not-eligible: Business context is not RENT'
        WHEN hch.consultant_type <> 'CIQ_FULL' THEN 'not-eligible: User consultant is not CIQ_FULL'
        WHEN lbc.status = 'EDITING' OR lbc.ts_first_publication IS NULL THEN 'not-eligible: House is not published yet, is in editing status or suspended'
        WHEN hl.ts_contract_signed IS NULL THEN 'not-eligible: House does not have a signed contract'
        WHEN vfl.hybrid_creation_order = 'SALE > RENT' THEN 'hybrid: House is a hybrid house converted from sale to rent'
        WHEN lbc.ts_first_publication >= DATE("2026-07-01") THEN 'new-listings: House listing published after the transition'
        WHEN lbc.ts_first_publication < DATE("2026-07-01")
            AND COALESCE(hl.listing_status, lbc.status) IN ('PUBLISHED', 'publicado')
            THEN 'ongoing-listings: House listing published before the transition and is currently available for rental'
        WHEN lbc.ts_first_publication < DATE("2026-07-01")
            AND hl.ts_contract_signed IS NOT NULL
            AND hl.dt_termination IS NULL
            THEN 'ongoing-rentals: House listing published before the transition and is currently rented'
        WHEN lbc.ts_first_publication < DATE("2026-07-01")
            AND hl.ts_contract_signed IS NOT NULL
            AND hl.dt_termination IS NOT NULL
            AND hl.has_republication IS FALSE
            THEN 'not-eligible: Contract was terminated, but has not generated a relisting'
        WHEN lbc.ts_first_publication < DATE("2026-07-01")
            AND hl.ts_contract_signed IS NOT NULL
            AND hl.dt_termination IS NOT NULL
            AND hl.has_republication IS TRUE
            THEN 'not-eligible: Contract was terminated and the house has generated a relisting'
    END AS pricing_type_reason,
    SPLIT(pricing_type_reason, ':')[0] AS pricing_type,
    ae.due_amount AS amount_paid,
    IF(
        hl.is_house_inactive IS TRUE, 
        TIMESTAMPDIFF(DAY, hl.ts_listing_version_start, COALESCE(hl.ts_listing_version_end, DATE(NOW()))), 
        0
    ) AS total_days_since_house_inactived,
    TIMESTAMPDIFF(DAY, hl.ts_publicated, DATE(NOW())) AS total_days_since_publish,
    ld.has_duplicates AS has_similiar_house_by_address_parsed,
    ahd.id_duplicity IS NOT NULL AS has_similiar_house_by_atlas,
    hl.has_republication,
    hl.is_first_contract_signed AS is_first_contract_signed_by_house,
    hl.is_last_contract_signed AS is_last_contract_signed_by_house,
    hl.is_last_version AS is_last_house_listing,
    hl.is_house_inactive,
    COALESCE(pricing_type, 'not-eligible') <> 'not-eligible' AS is_eligible,
    ae.dt_occurrence IS NOT NULL AS is_paid,
    ae.dt_occurrence AS dt_paid,
    hl.dt_termination AS dt_contract_termination,
    hl.ts_contract_signed,
    hl.ts_next_contract_signed,
    hl.ts_previous_contract_signed,
    hl.ts_publicated,
    IF(hl.is_house_inactive IS TRUE, hl.ts_listing_version_start, NULL) AS ts_house_inactived,
    hch.ts_house_registration,
    lbc.ts_first_publication AS ts_first_listing,
    NOW() AS ts_load,
    YEAR(hch.ts_house_registration) AS year,
    MONTH(hch.ts_house_registration) AS month,
    DAY(hch.ts_house_registration) AS day
FROM
    core_house.house AS h
LEFT JOIN
    house_city_group AS hcg
        ON hcg.id_house = h.id_house
        AND hcg.is_matched IS TRUE
LEFT JOIN
    datalake_ebdb_clean.listing_business_context AS lbc
        ON lbc.id_house = h.id_house
LEFT JOIN
    house_listing AS hl
        ON hl.id_house = h.id_house
LEFT JOIN
    house_consultant_history AS hch
        ON hch.id_house = h.id_house
LEFT JOIN
    datalake_listing_deduplication.listing_deduplication AS ld
        ON ld.id_house = h.id_house
LEFT JOIN
    datalake_listing_deduplication.atlas_house_deduplication AS ahd
        ON ahd.id_house = h.id_house
        AND ahd.is_last_duplicity IS TRUE
LEFT JOIN
    datalake_listing_deduplication.valid_first_listing AS vfl
        ON vfl.id_house = h.id_house
LEFT JOIN
    datalake_robin_hood.accounting_entry AS ae
        ON TRY_CAST(ae.id_house AS BIGINT) = h.id_house
        AND TRY_CAST(ae.id_contract AS BIGINT) = hl.id_contract
        AND LOWER(TRIM(ae.source_code)) = 'ciq-listing-purchase'
        AND ae.ts_blocked IS NULL
LEFT JOIN
    supply_source_rent AS ssr
        ON ssr.id_house = h.id_house