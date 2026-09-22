WITH
-- Rent listing versions (ebdb house_listing) enriched with core contract fields; not filtered by LBC — grain is one row per signed rent id_contract.
house_listing AS (
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
-- Latest non-canceled sale agreement (CCV) per house; the SALE arm retains id_offer separately.
sale_agreement_by_house AS (
    SELECT
        id_house,
        id_offer,
        ts_contract_signed
    FROM
        (
            SELECT
                so.id_house,
                so.id_offer,
                so.ts_sale_agreement_signed AS ts_contract_signed,
                ROW_NUMBER() OVER (
                    PARTITION BY so.id_house
                    ORDER BY so.ts_sale_agreement_signed DESC
                ) AS sale_agreement_rank
            FROM
                datalake_sale_offer.sale_offer AS so
            WHERE
                so.ts_sale_agreement_signed IS NOT NULL
                AND COALESCE(so.is_ccv_canceled, FALSE) = FALSE
        ) AS ranked_sale_agreement
    WHERE
        sale_agreement_rank = 1
),
-- Earliest CIQ agency registration per house (for partition columns / ts_house_registration).
house_registration AS (
    SELECT
        hch.id_house,
        MIN(hch.ts_agency_created) AS ts_house_registration
    FROM
        datalake_big_agent.house_consultant_history AS hch
    GROUP BY
        hch.id_house
),
-- Last CIQ per listing (same grain as FL Valid: house_listing_consultant.is_last_ciq_on_listing).
-- RENT keeps id_listing; SALE is house-level (listing id null).
house_listing_ciq AS (
    SELECT
        cons.id_house,
        IF(cons.business_context = 'RENT', cons.id_listing, CAST(NULL AS BIGINT)) AS id_house_listing,
        cons.id_enrollment,
        cons.id_partner,
        cons.id_user,
        cons.consultant_type,
        cons.business_context,
        hr.ts_house_registration
    FROM
        datalake_big_agent.house_listing_consultant AS cons
    LEFT JOIN
        house_registration AS hr
            ON hr.id_house = cons.id_house
    WHERE
        cons.is_last_ciq_on_listing IS TRUE
),
-- Normalize house city string from core_house for region lookup.
house_city_clean AS (
    SELECT
        id_house,
        TRIM(
            REGEXP_REPLACE(
                TRANSLATE(
                    REGEXP_EXTRACT(TRIM(LOWER(h.city)), '^([^,/-]+)', 1),
                    'áàâãäéèêëíìîïóòôõöúùûüç',
                    'aaaaaeeeeiiiiooooouuuuc'
                ),
                '[^a-z ]',
                ''
            )
        ) AS city_name,
        REGEXP_REPLACE(
            TRANSLATE(
                REGEXP_EXTRACT(TRIM(LOWER(h.city)), '^([^,/-]+)', 1),
                'áàâãäéèêëíìîïóòôõöúùûüç',
                'aaaaaeeeeiiiiooooouuuuc'
            ),
            '[^a-z]',
            ''
        ) AS city_name_clean
    FROM
        core_house.house AS h
),
-- Latest region row per city_name for city_group mapping.
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
-- Prefixes of each house city for STARTSWITH matching via equi-join (not nested-loop).
house_city_prefixes AS (
    SELECT
        h.id_house,
        SUBSTRING(h.city_name_clean, 1, prefix_length) AS city_prefix
    FROM
        house_city_clean AS h
    LATERAL VIEW EXPLODE(SEQUENCE(1, LENGTH(h.city_name_clean))) exploded_prefix AS prefix_length
    WHERE
        LENGTH(h.city_name_clean) >= 1
),
-- Best prefix city_group per house (longest matching region city_name_clean).
prefix_city_match AS (
    SELECT
        hcp.id_house,
        cg3.city_name,
        cg3.city_group,
        cg3.city_name_clean,
        ROW_NUMBER() OVER (
            PARTITION BY hcp.id_house
            ORDER BY LENGTH(hcp.city_prefix) DESC
        ) = 1 AS is_best_prefix
    FROM
        house_city_prefixes AS hcp
    INNER JOIN
        city_group AS cg3
            ON hcp.city_prefix = cg3.city_name_clean
            AND cg3.is_last_updated IS TRUE
),
-- Best fuzzy city_group per house; 3-char block is the hash key, LEVENSHTEIN is a filter.
fuzzy_city_match AS (
    SELECT
        h.id_house,
        cg2.city_name,
        cg2.city_group,
        cg2.city_name_clean,
        ROW_NUMBER() OVER (
            PARTITION BY h.id_house
            ORDER BY LEVENSHTEIN(h.city_name_clean, cg2.city_name_clean)
        ) = 1 AS is_best_fuzzy
    FROM
        house_city_clean AS h
    INNER JOIN
        city_group AS cg2
            ON SUBSTRING(h.city_name_clean, 1, 3) = SUBSTRING(cg2.city_name_clean, 1, 3)
            AND LEVENSHTEIN(h.city_name_clean, cg2.city_name_clean) <= 2
            AND cg2.is_last_updated IS TRUE
    WHERE
        LENGTH(h.city_name_clean) >= 3
        AND LENGTH(cg2.city_name_clean) >= 3
),
-- Match each house to a city_name / city_group (exact, then fuzzy, then prefix).
house_city_group AS (
    SELECT
        h.id_house,
        COALESCE(cg.city_name, fcm.city_name, pcm.city_name, h.city_name) AS city_name,
        COALESCE(cg.city_group, fcm.city_group, pcm.city_group) AS city_group,
        ROW_NUMBER() OVER (
            PARTITION BY h.id_house
            ORDER BY
                IF(cg.city_name IS NOT NULL, 0, 1),
                LEVENSHTEIN(
                    h.city_name_clean,
                    COALESCE(fcm.city_name_clean, pcm.city_name_clean)
                )
        ) = 1 AS is_matched
    FROM
        house_city_clean AS h
    LEFT JOIN
        city_group AS cg
            ON h.city_name_clean = cg.city_name_clean
            AND cg.is_last_updated IS TRUE
    LEFT JOIN
        fuzzy_city_match AS fcm
            ON fcm.id_house = h.id_house
            AND fcm.is_best_fuzzy IS TRUE
    LEFT JOIN
        prefix_city_match AS pcm
            ON pcm.id_house = h.id_house
            AND pcm.is_best_prefix IS TRUE
),
-- CIQ supply funnel source label for RENT (deduped per house).
supply_source_rent AS (
    SELECT DISTINCT
        id_house,
        IF(company_report_origin = "CIQ - Operations", "CIQ", company_report_origin) AS supply_source
    FROM
        datalake_ciq.ciq_supply_events_tracking
    WHERE
        business_context = 'RENT'
        AND id_funnel_step = 6
),
-- Rent contracts on houses with no listing_business_context row (legacy); keeps rows with NULL business_context.
houses_missing_any_lbc AS (
    SELECT DISTINCT
        hl.id_house
    FROM
        house_listing AS hl
    WHERE
        hl.id_contract IS NOT NULL
        AND NOT EXISTS (
            SELECT
                1
            FROM
                datalake_ebdb_clean.listing_business_context AS lbc_chk
            WHERE
                lbc_chk.id_house = hl.id_house
        )
),
-- Compra de Carteira payment grain: one row per rent id_contract; last CIQ on that listing version.
listing_purchase_rent AS (
    SELECT
        XXHASH64(
            hl.id_house,
            hl.id_house_listing,
            ca.id_partner,
            ca.id_user,
            CAST('RENT' AS STRING),
            ca.consultant_type
        ) AS id_listing_purchase,
        hl.id_house,
        TRY_CAST(ca.id_partner AS BIGINT) AS id_partner,
        hl.id_house_listing,
        hl.id_contract,
        CAST(NULL AS BIGINT) AS id_offer,
        h.id_owner,
        ca.id_user AS id_ciq_user,
        ca.id_enrollment,
        ae.id AS id_accounting_entry,
        ld.id_address_parsed_short AS id_address_parsed_duplicity,
        ahd.id_duplicity AS id_atlas_duplicity,
        ld.address_full AS address,
        ld.first_listing_order AS parsed_first_listing_order,
        hcg.city_name,
        hcg.city_group,
        ssr.supply_source,
        IF(legacy_lbc.id_house IS NOT NULL, CAST(NULL AS STRING), CAST('RENT' AS STRING)) AS business_context,
        ca.consultant_type,
        UPPER(COALESCE(hl.listing_status, lbc.status)) AS listing_status,
        hl.listing_category,
        hl.contract_status,
        CASE
            WHEN legacy_lbc.id_house IS NOT NULL
                THEN 'not-eligible: Missing listing business context on house (legacy rent contract without RENT/SALE context in listing_business_context)'
            WHEN lbc.id_house IS NULL THEN 'not-eligible: Missing RENT listing business context on house'
            WHEN hl.ts_contract_signed IS NULL THEN "not-eligible: Don't have a contract signed yet"
            WHEN ca.consultant_type NOT IN ('CIQ_FULL', 'PRO_ACQUIRER') OR ca.consultant_type IS NULL
                THEN 'not-eligible: User consultant is not CIQ_FULL or PRO_ACQUIRER, or no last CIQ on listing'
            WHEN ca.id_user IS NULL
                THEN 'not-eligible: No active CIQ agent attributed to the house'
            WHEN CAST(FROM_UTC_TIMESTAMP(hl.ts_contract_signed, 'America/Sao_Paulo') AS DATE) < DATE('2026-07-01')
                THEN 'not-eligible: Contract signed before the transition'
            WHEN CAST(FROM_UTC_TIMESTAMP(lbc.ts_first_publication, 'America/Sao_Paulo') AS DATE) >= DATE('2026-07-01')
                AND vfl.hybrid_creation_order = 'SALE > RENT'
                THEN 'hybrid: House is a hybrid house converted from sale to rent'
            WHEN CAST(FROM_UTC_TIMESTAMP(lbc.ts_first_publication, 'America/Sao_Paulo') AS DATE) >= DATE('2026-07-01')
                AND CAST(FROM_UTC_TIMESTAMP(hl.ts_contract_signed, 'America/Sao_Paulo') AS DATE) >= DATE('2026-07-01')
                THEN 'new-listings: House listing published and rented after the transition'
            WHEN CAST(FROM_UTC_TIMESTAMP(lbc.ts_first_publication, 'America/Sao_Paulo') AS DATE) < DATE('2026-07-01')
                AND hl.ts_previous_contract_signed IS NULL
                AND CAST(FROM_UTC_TIMESTAMP(hl.ts_contract_signed, 'America/Sao_Paulo') AS DATE) >= DATE('2026-07-01')
                THEN 'ongoing-listings: House listing published before the transition and first rented after the transition'
            WHEN CAST(FROM_UTC_TIMESTAMP(lbc.ts_first_publication, 'America/Sao_Paulo') AS DATE) < DATE('2026-07-01')
                AND hl.ts_previous_contract_signed IS NOT NULL
                AND CAST(FROM_UTC_TIMESTAMP(hl.ts_contract_signed, 'America/Sao_Paulo') AS DATE) >= DATE('2026-07-01')
                THEN 'ongoing-rentals: House listing published before the transition and re-rented after the transition'
        END AS initial_pricing_type_reason,
        SPLIT(initial_pricing_type_reason, ':')[0] AS initial_pricing_type,
        CAST(ae.due_amount AS DECIMAL(10, 2)) AS amount_paid,
        IF(
            hl.is_house_inactive IS TRUE,
            TIMESTAMPDIFF(DAY, hl.ts_listing_version_start, COALESCE(hl.ts_listing_version_end, DATE(NOW()))),
            0
        ) AS total_days_since_house_inactived,
        IF(
            hl.ts_publicated IS NOT NULL,
            TIMESTAMPDIFF(DAY, hl.ts_publicated, DATE(NOW())),
            CAST(NULL AS INT)
        ) AS total_days_since_publish,
        ld.has_duplicates AS has_similiar_house_by_address_parsed,
        ahd.id_duplicity IS NOT NULL AS has_similiar_house_by_atlas,
        hl.has_republication,
        hl.is_first_contract_signed AS is_first_contract_signed_by_house,
        hl.is_last_contract_signed AS is_last_contract_signed_by_house,
        hl.is_last_version AS is_last_house_listing,
        COALESCE(hl.is_house_inactive, FALSE) AS is_house_inactive,
        ae.dt_occurrence IS NOT NULL AS is_paid,
        ae.dt_occurrence AS dt_paid,
        hl.dt_termination AS dt_contract_termination,
        hl.ts_contract_signed,
        FROM_UTC_TIMESTAMP(hl.ts_contract_signed, 'America/Sao_Paulo') AS ts_contract_signed_local_tz,
        hl.ts_next_contract_signed,
        hl.ts_previous_contract_signed,
        hl.ts_publicated,
        IF(hl.is_house_inactive IS TRUE, hl.ts_listing_version_start, NULL) AS ts_house_inactived,
        ca.ts_house_registration,
        lbc.ts_first_publication AS ts_first_listing,
        FROM_UTC_TIMESTAMP(lbc.ts_first_publication, 'America/Sao_Paulo') AS ts_first_listing_local_tz,
        NOW() AS ts_load,
        YEAR(COALESCE(ca.ts_house_registration, hl.ts_publicated, lbc.ts_first_publication)) AS year,
        MONTH(COALESCE(ca.ts_house_registration, hl.ts_publicated, lbc.ts_first_publication)) AS month,
        DAY(COALESCE(ca.ts_house_registration, hl.ts_publicated, lbc.ts_first_publication)) AS day
    FROM
        house_listing AS hl
    INNER JOIN
        core_house.house AS h
            ON h.id_house = hl.id_house
    LEFT JOIN
        datalake_ebdb_clean.listing_business_context AS lbc
            ON lbc.id_house = hl.id_house
            AND lbc.business_context = 'RENT'
    LEFT JOIN
        houses_missing_any_lbc AS legacy_lbc
            ON legacy_lbc.id_house = hl.id_house
    LEFT JOIN
        house_listing_ciq AS ca
            ON ca.business_context = 'RENT'
            AND ca.id_house = hl.id_house
            AND ca.id_house_listing = hl.id_house_listing
    LEFT JOIN
        house_city_group AS hcg
            ON hcg.id_house = hl.id_house
            AND hcg.is_matched IS TRUE
    LEFT JOIN
        datalake_listing_deduplication.listing_deduplication AS ld
            ON ld.id_house = hl.id_house
    LEFT JOIN
        datalake_listing_deduplication.atlas_house_deduplication AS ahd
            ON ahd.id_house = hl.id_house
            AND ahd.is_last_duplicity IS TRUE
    LEFT JOIN
        datalake_listing_deduplication.valid_first_listing AS vfl
            ON vfl.id_house = hl.id_house
    LEFT JOIN
        datalake_robin_hood.accounting_entry AS ae
            ON TRY_CAST(ae.id_contract AS BIGINT) = hl.id_contract
            AND LOWER(TRIM(ae.source_code)) = '1p-portfolio-purchase'
            AND ae.ts_blocked IS NULL
    LEFT JOIN
        supply_source_rent AS ssr
            ON ssr.id_house = hl.id_house
    WHERE
        hl.id_contract IS NOT NULL
),
-- Duplicity-only SALE rows (not eligible for payment); requires SALE LBC + CCV; last SALE CIQ on the house.
listing_purchase_sale AS (
    SELECT
        XXHASH64(
            h.id_house,
            CAST(-1 AS BIGINT),
            ca.id_partner,
            ca.id_user,
            CAST('SALE' AS STRING),
            ca.consultant_type
        ) AS id_listing_purchase,
        h.id_house,
        TRY_CAST(ca.id_partner AS BIGINT) AS id_partner,
        CAST(NULL AS BIGINT) AS id_house_listing,
        CAST(NULL AS BIGINT) AS id_contract,
        TRY_CAST(sa.id_offer AS BIGINT) AS id_offer,
        h.id_owner,
        ca.id_user AS id_ciq_user,
        ca.id_enrollment,
        CAST(NULL AS BIGINT) AS id_accounting_entry,
        ld.id_address_parsed_short AS id_address_parsed_duplicity,
        ahd.id_duplicity AS id_atlas_duplicity,
        ld.address_full AS address,
        ld.first_listing_order AS parsed_first_listing_order,
        hcg.city_name,
        hcg.city_group,
        CAST(NULL AS STRING) AS supply_source,
        CAST('SALE' AS STRING) AS business_context,
        ca.consultant_type,
        UPPER(lbc.status) AS listing_status,
        CAST(NULL AS STRING) AS listing_category,
        CAST(NULL AS STRING) AS contract_status,
        'not-eligible: Business context is not RENT' AS initial_pricing_type_reason,
        CAST('not-eligible' AS STRING) AS initial_pricing_type,
        CAST(NULL AS DECIMAL(10, 2)) AS amount_paid,
        CAST(0 AS INT) AS total_days_since_house_inactived,
        CAST(NULL AS INT) AS total_days_since_publish,
        ld.has_duplicates AS has_similiar_house_by_address_parsed,
        ahd.id_duplicity IS NOT NULL AS has_similiar_house_by_atlas,
        CAST(NULL AS BOOLEAN) AS has_republication,
        CAST(NULL AS BOOLEAN) AS is_first_contract_signed_by_house,
        CAST(NULL AS BOOLEAN) AS is_last_contract_signed_by_house,
        CAST(NULL AS BOOLEAN) AS is_last_house_listing,
        CAST(FALSE AS BOOLEAN) AS is_house_inactive,
        CAST(FALSE AS BOOLEAN) AS is_paid,
        CAST(NULL AS DATE) AS dt_paid,
        CAST(NULL AS DATE) AS dt_contract_termination,
        sa.ts_contract_signed,
        FROM_UTC_TIMESTAMP(sa.ts_contract_signed, 'America/Sao_Paulo') AS ts_contract_signed_local_tz,
        CAST(NULL AS TIMESTAMP) AS ts_next_contract_signed,
        CAST(NULL AS TIMESTAMP) AS ts_previous_contract_signed,
        CAST(NULL AS TIMESTAMP) AS ts_publicated,
        CAST(NULL AS TIMESTAMP) AS ts_house_inactived,
        ca.ts_house_registration,
        lbc.ts_first_publication AS ts_first_listing,
        FROM_UTC_TIMESTAMP(lbc.ts_first_publication, 'America/Sao_Paulo') AS ts_first_listing_local_tz,
        NOW() AS ts_load,
        YEAR(COALESCE(ca.ts_house_registration, lbc.ts_first_publication)) AS year,
        MONTH(COALESCE(ca.ts_house_registration, lbc.ts_first_publication)) AS month,
        DAY(COALESCE(ca.ts_house_registration, lbc.ts_first_publication)) AS day
    FROM
        core_house.house AS h
    INNER JOIN
        datalake_ebdb_clean.listing_business_context AS lbc
            ON lbc.id_house = h.id_house
            AND lbc.business_context = 'SALE'
    INNER JOIN
        sale_agreement_by_house AS sa
            ON sa.id_house = h.id_house
    LEFT JOIN
        house_listing_ciq AS ca
            ON ca.business_context = 'SALE'
            AND ca.id_house = h.id_house
    LEFT JOIN
        house_city_group AS hcg
            ON hcg.id_house = h.id_house
            AND hcg.is_matched IS TRUE
    LEFT JOIN
        datalake_listing_deduplication.listing_deduplication AS ld
            ON ld.id_house = h.id_house
    LEFT JOIN
        datalake_listing_deduplication.atlas_house_deduplication AS ahd
            ON ahd.id_house = h.id_house
            AND ahd.is_last_duplicity IS TRUE
),
-- Final enrich output: rent payment rows ∪ sale context rows (no overlap at id_house + business_context + contract/offer grain).
listing_purchase AS (
    SELECT
        id_listing_purchase,
        id_house,
        id_partner,
        id_house_listing,
        id_contract,
        id_offer,
        id_owner,
        id_ciq_user,
        id_enrollment,
        id_accounting_entry,
        id_address_parsed_duplicity,
        id_atlas_duplicity,
        address,
        parsed_first_listing_order,
        city_name,
        city_group,
        supply_source,
        business_context,
        consultant_type,
        listing_status,
        listing_category,
        contract_status,
        initial_pricing_type_reason,
        initial_pricing_type,
        amount_paid,
        total_days_since_house_inactived,
        total_days_since_publish,
        has_similiar_house_by_address_parsed,
        has_similiar_house_by_atlas,
        has_republication,
        is_first_contract_signed_by_house,
        is_last_contract_signed_by_house,
        is_last_house_listing,
        is_house_inactive,
        is_paid,
        dt_paid,
        dt_contract_termination,
        ts_contract_signed,
        ts_contract_signed_local_tz,
        ts_next_contract_signed,
        ts_previous_contract_signed,
        ts_publicated,
        ts_house_inactived,
        ts_house_registration,
        ts_first_listing,
        ts_first_listing_local_tz,
        ts_load,
        year,
        month,
        day
    FROM
        listing_purchase_rent
    UNION ALL
    SELECT
        id_listing_purchase,
        id_house,
        id_partner,
        id_house_listing,
        id_contract,
        id_offer,
        id_owner,
        id_ciq_user,
        id_enrollment,
        id_accounting_entry,
        id_address_parsed_duplicity,
        id_atlas_duplicity,
        address,
        parsed_first_listing_order,
        city_name,
        city_group,
        supply_source,
        business_context,
        consultant_type,
        listing_status,
        listing_category,
        contract_status,
        initial_pricing_type_reason,
        initial_pricing_type,
        amount_paid,
        total_days_since_house_inactived,
        total_days_since_publish,
        has_similiar_house_by_address_parsed,
        has_similiar_house_by_atlas,
        has_republication,
        is_first_contract_signed_by_house,
        is_last_contract_signed_by_house,
        is_last_house_listing,
        is_house_inactive,
        is_paid,
        dt_paid,
        dt_contract_termination,
        ts_contract_signed,
        ts_contract_signed_local_tz,
        ts_next_contract_signed,
        ts_previous_contract_signed,
        ts_publicated,
        ts_house_inactived,
        ts_house_registration,
        ts_first_listing,
        ts_first_listing_local_tz,
        ts_load,
        year,
        month,
        day
    FROM
        listing_purchase_sale
)
SELECT
    id_listing_purchase,
    id_house,
    id_partner,
    id_house_listing,
    id_contract,
    id_offer,
    id_owner,
    id_ciq_user,
    id_enrollment,
    id_accounting_entry,
    id_address_parsed_duplicity,
    id_atlas_duplicity,
    address,
    parsed_first_listing_order,
    city_name,
    city_group,
    supply_source,
    business_context,
    consultant_type,
    listing_status,
    listing_category,
    contract_status,
    initial_pricing_type_reason,
    initial_pricing_type,
    amount_paid,
    total_days_since_house_inactived,
    total_days_since_publish,
    has_similiar_house_by_address_parsed,
    has_similiar_house_by_atlas,
    has_republication,
    is_first_contract_signed_by_house,
    is_last_contract_signed_by_house,
    is_last_house_listing,
    is_house_inactive,
    is_paid,
    dt_paid,
    dt_contract_termination,
    ts_contract_signed,
    ts_contract_signed_local_tz,
    ts_next_contract_signed,
    ts_previous_contract_signed,
    ts_publicated,
    ts_house_inactived,
    ts_house_registration,
    ts_first_listing,
    ts_first_listing_local_tz,
    ts_load,
    year,
    month,
    day
FROM
    listing_purchase