WITH house_contexts AS (
    SELECT
        h.id AS id_house,
        ANY(lbc.business_context = 'SALE') AS is_for_sale,
        ANY(lbc.business_context = 'RENT' OR lbc.id IS NULL) AS is_for_rent
    FROM
        datalake_ebdb_clean.house AS h
    LEFT JOIN
        datalake_ebdb_clean.listing_business_context AS lbc
            ON h.id = lbc.id_house
    GROUP BY 1
),
house_summary AS (
    SELECT
        COUNT(*) AS total_houses,
        COUNT_IF(is_for_sale) AS total_sale_houses,
        COUNT_IF(is_for_rent) AS total_rent_houses
    FROM
        house_contexts
),
amenity_usage_information AS (
    SELECT
        ia.id_amenities AS id_amenity,
        COUNT(*)/MIN(hs.total_houses) AS ratio_houses_filled,
        COUNT_IF(hc.is_for_sale)/MIN(hs.total_sale_houses) AS ratio_sale_houses_filled,
        COUNT_IF(hc.is_for_rent)/MIN(hs.total_rent_houses) AS ratio_rent_houses_filled,
        COUNT_IF(ia.has_characteristic)/MIN(hs.total_houses) AS ratio_houses_true,
        COUNT_IF(ia.has_characteristic AND hc.is_for_sale)/MIN(hs.total_sale_houses) AS ratio_sale_houses_true,
        COUNT_IF(ia.has_characteristic AND hc.is_for_rent)/MIN(hs.total_rent_houses) AS ratio_rent_houses_true,
        FALSE AS is_condo_amenity,
        MIN(ia.ts_created) AS ts_first_usage,
        MAX(ia.ts_created) AS ts_last_usage
    FROM
        datalake_ebdb_clean.info_amenities AS ia,
        house_summary AS hs
    LEFT JOIN
        house_contexts AS hc
            ON hc.id_house = ia.id_house
    GROUP BY
        ia.id_amenities
    UNION ALL
    SELECT
        ia.id_condo_amenities AS id_amenity,
        COUNT(*)/MIN(hs.total_houses) AS ratio_houses_filled,
        COUNT_IF(hc.is_for_sale)/MIN(hs.total_sale_houses) AS ratio_sale_houses_filled,
        COUNT_IF(hc.is_for_rent)/MIN(hs.total_rent_houses) AS ratio_rent_houses_filled,
        COUNT_IF(ia.has_characteristic)/MIN(hs.total_houses) AS ratio_houses_true,
        COUNT_IF(ia.has_characteristic AND hc.is_for_sale)/MIN(hs.total_sale_houses) AS ratio_sale_houses_true,
        COUNT_IF(ia.has_characteristic AND hc.is_for_rent)/MIN(hs.total_rent_houses) AS ratio_rent_houses_true,
        TRUE AS is_condo_amenity,
        MIN(ia.ts_created) AS ts_first_usage,
        MAX(ia.ts_created) AS ts_last_usage
    FROM
        datalake_ebdb_clean.info_condo_amenities AS ia,
        house_summary AS hs
    LEFT JOIN
        house_contexts AS hc
            ON hc.id_house = ia.id_house
    GROUP BY
        ia.id_condo_amenities
    UNION ALL
    SELECT
        0 AS id_amenity,
        COUNT_IF(ia.has_elevator IS NOT NULL)/MIN(hs.total_houses) AS ratio_houses_filled,
        COUNT_IF(ia.has_elevator IS NOT NULL AND hc.is_for_sale)/MIN(hs.total_sale_houses) AS ratio_sale_houses_filled,
        COUNT_IF(ia.has_elevator IS NOT NULL AND hc.is_for_rent)/MIN(hs.total_rent_houses) AS ratio_rent_houses_filled,
        COUNT_IF(ia.has_elevator)/MIN(hs.total_houses) AS ratio_houses_true,
        COUNT_IF(ia.has_elevator AND hc.is_for_sale)/MIN(hs.total_sale_houses) AS ratio_sale_houses_true,
        COUNT_IF(ia.has_elevator AND hc.is_for_rent)/MIN(hs.total_rent_houses) AS ratio_rent_houses_true,
        TRUE AS is_condo_amenity,
        MIN(CASE WHEN ia.has_elevator IS NOT NULL THEN ia.dt_creation END) AS ts_first_usage,
        MAX(CASE WHEN ia.has_elevator IS NOT NULL THEN ia.dt_creation END) AS ts_last_usage
    FROM
        datalake_ebdb_clean.house AS ia,
        house_summary AS hs
    LEFT JOIN
        house_contexts AS hc
            ON hc.id_house = ia.id
),
base_amenities AS (
    SELECT
        id AS id_amenity,
        code,
        name,
        slug,
        FALSE AS is_condo_amenity,
        is_active,
        ts_created,
        ts_updated
    FROM
        datalake_ebdb_clean.amenities
    UNION ALL
    SELECT
        id_condo_amenity AS id_amenity,
        code,
        name,
        slug,
        TRUE AS is_condo_amenity,
        is_active,
        ts_created,
        ts_updated
    FROM
        datalake_ebdb_clean.condo_amenities
    UNION ALL
    SELECT -- Elevator is not in the amenities table, even though it is considered one in the business sense. So we're adding it here manually.
        0 AS id_amenity,
        'ELEVADOR' AS code,
        'Elevador' AS name,
        'elevador' AS slug,
        TRUE AS is_condo_amenity,
        TRUE AS is_active,
        NULL AS ts_created,
        NULL AS ts_updated
)
SELECT
    ba.id_amenity,
    ba.code,
    ba.name,
    ba.slug,
    ba.is_condo_amenity,
    ba.is_active,
    aui.ratio_houses_filled,
    aui.ratio_sale_houses_filled,
    aui.ratio_rent_houses_filled,
    aui.ratio_houses_true,
    aui.ratio_sale_houses_true,
    aui.ratio_rent_houses_true,
    aui.ts_first_usage,
    aui.ts_last_usage
FROM
    base_amenities AS ba
LEFT JOIN
    amenity_usage_information AS aui
        ON ba.id_amenity = aui.id_amenity
        AND ba.is_condo_amenity = aui.is_condo_amenity
