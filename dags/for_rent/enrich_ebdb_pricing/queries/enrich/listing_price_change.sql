WITH house_aud AS (
    SELECT
        h_aud.id_house,
        lbc.business_context,
        r.id_user AS id_user_revision,
        h_aud.rev AS id_revision,
        h_aud.rev_type,
        h_aud.rent AS rent_price,
        h_aud.sale_price AS sale_price,
        lbc.ts_first_publication,
        CASE
            WHEN lbc.ts_first_publication >= r.ts_revision OR lbc.ts_first_publication IS NULL THEN 'UNPUBLISHED'
            ELSE 'PUBLISHED'
        END AS status_threshold,
        /* The purpose of creating this threshold is to take the last line before the listing is published, so that we have the first price. */
        ROW_NUMBER() OVER (PARTITION BY h_aud.id_house, lbc.business_context, IF(lbc.ts_first_publication >= r.ts_revision OR lbc.ts_first_publication IS NULL, 'UNPUBLISHED', 'PUBLISHED') ORDER BY h_aud.rev DESC) AS threshold,
        /* We can't trust the mod_sale_price flag in 100% of cases, so we need to check if the price has changed manually. */
        LAG(h_aud.rent) OVER (PARTITION BY h_aud.id_house, lbc.business_context ORDER BY r.ts_revision, h_aud.rev) IS DISTINCT FROM h_aud.rent AS has_rent_price_changed,
        LAG(h_aud.sale_price) OVER (PARTITION BY h_aud.id_house, lbc.business_context ORDER BY r.ts_revision, h_aud.rev) IS DISTINCT FROM h_aud.sale_price AS has_sale_price_changed,
        DATE(r.ts_revision) AS dt_change,
        r.ts_revision
    FROM
        datalake_ebdb_clean.house_aud AS h_aud
    INNER JOIN
        datalake_ebdb_user.user_revision_entity AS r
            ON h_aud.rev = r.id
    INNER JOIN
        datalake_ebdb_clean.listing_business_context AS lbc
            ON lbc.id_house = h_aud.id_house
    WHERE
        (rent > 1
        OR sale_price > 1)
),
rent_price_threshold AS (
    SELECT
        id_house,
        business_context,
        id_user_revision,
        id_revision,
        rent_price,
        dt_change,
        ts_revision
    FROM
        house_aud
    WHERE
        /* Filter the last price before publication and all changes while published. (Avoids price changes before deciding on the price that will actually be published). */
        business_context = 'RENT'
        AND
        (
            (status_threshold = 'UNPUBLISHED' AND threshold = 1)
            OR (status_threshold = 'PUBLISHED' AND has_rent_price_changed)
        )
),
sale_price_threshold AS (
    SELECT
        id_house,
        business_context,
        id_user_revision,
        id_revision,
        sale_price,
        dt_change,
        ts_revision
    FROM
        house_aud
    WHERE
        /* Filter the last price before publication and all changes while published. (Avoids price changes before deciding on the price that will actually be published). */
        business_context = 'SALE'
        AND (
            (status_threshold = 'UNPUBLISHED' AND threshold = 1)
            OR (status_threshold = 'PUBLISHED' AND has_sale_price_changed)
        )
),
rent_price_lag AS (
    SELECT
        id_house,
        id_user_revision,
        id_revision,
        business_context,
        rent_price,
        LAG(rent_price) OVER (PARTITION BY id_house ORDER BY ts_revision) AS lag_price,
        dt_change,
        ts_revision
    FROM
        rent_price_threshold
    QUALIFY
        (lag_price IS DISTINCT FROM rent_price OR lag_price IS NULL) AND rent_price IS NOT NULL
),
sale_price_lag AS (
    SELECT
        id_house,
        id_user_revision,
        id_revision,
        business_context,
        sale_price,
        LAG(sale_price) OVER (PARTITION BY id_house ORDER BY ts_revision) AS lag_price,
        dt_change,
        ts_revision
    FROM
        sale_price_threshold
    QUALIFY
        (lag_price IS DISTINCT FROM sale_price OR lag_price IS NULL) AND sale_price IS NOT NULL
),
rent_price_interval AS (
    SELECT
        id_house,
        id_user_revision,
        id_revision,
        business_context,
        rent_price,
        lag_price,
        IF(ROW_NUMBER() OVER (PARTITION BY id_house, dt_change ORDER BY ts_revision DESC) = 1, TRUE, FALSE) AS is_last_price_of_day,
        ts_revision AS ts_price_started,
        LEAD(ts_revision) OVER (PARTITION BY id_house ORDER BY ts_revision) AS ts_price_ended
    FROM
        rent_price_lag
),
sale_price_interval AS (
    SELECT
        id_house,
        id_user_revision,
        id_revision,
        business_context,
        sale_price,
        lag_price,
        IF(ROW_NUMBER() OVER (PARTITION BY id_house, dt_change ORDER BY ts_revision DESC) = 1, TRUE, FALSE) AS is_last_price_of_day,
        ts_revision AS ts_price_started,
        LEAD(ts_revision) OVER (PARTITION BY id_house ORDER BY ts_revision) AS ts_price_ended
    FROM
        sale_price_lag
),
rent_status_versions AS (
    SELECT DISTINCT
        hl.id_house,
        hl.id_house_listing,
        hl.ts_listing_version_start,
        hl.ts_listing_version_end
    FROM
        datalake_ebdb_listing.house_listing AS hl
    INNER JOIN
        datalake_ebdb_listing.business_context_history AS bch
            ON hl.id_house = bch.id_house
            AND hl.ts_listing_version_start <= bch.ts_state_started
            AND COALESCE(bch.ts_state_ended, CURRENT_TIMESTAMP) <= COALESCE(hl.ts_listing_version_end, CURRENT_TIMESTAMP)
    WHERE
        bch.business_context = 'RENT'
        AND hl.id_house_listing IS NOT NULL
),
rent_status_version_order AS (
    SELECT
        *,
        ROW_NUMBER() OVER(PARTITION BY id_house ORDER BY ts_listing_version_start ASC) = 1 AS is_first_version
    FROM
        rent_status_versions
),
sale_timestamp_version AS (
    SELECT
        id_house,
        id_sale_listing,
        ts_status_started,
        ts_status_ended,
        ROW_NUMBER() OVER(PARTITION BY id_sale_listing ORDER BY ts_status_started ASC) AS rn_start,
        ROW_NUMBER() OVER(PARTITION BY id_sale_listing ORDER BY COALESCE(ts_status_ended, CURRENT_TIMESTAMP) DESC) AS rn_end
    FROM
        datalake_sale_listings.sale_listing_status
),
sale_status_version_order AS (
    SELECT
        stv1.id_house,
        stv1.id_sale_listing AS id_house_listing,
        ROW_NUMBER() OVER(PARTITION BY stv1.id_house ORDER BY stv1.ts_status_started ASC) = 1 AS is_first_version,
        stv1.ts_status_started AS ts_listing_version_start,
        stv2.ts_status_ended AS ts_listing_version_end
    FROM
        sale_timestamp_version AS stv1
    INNER JOIN
        sale_timestamp_version AS stv2
            ON stv1.id_sale_listing = stv2.id_sale_listing
            AND stv1.rn_start = stv2.rn_end
    WHERE
        stv1.rn_start = 1
        AND stv1.id_sale_listing IS NOT NULL
),
rent_price_changes_listing AS (
    SELECT
        pi.id_house,
        rsvo.id_house_listing,
        pi.id_user_revision,
        pi.id_revision,
        pi.business_context,
        pi.rent_price AS price,
        LAG(pi.rent_price) OVER (PARTITION BY pi.id_house ORDER BY ts_price_started) AS lag_price,
        pi.is_last_price_of_day,
        IF(pi.ts_price_started < rsvo.ts_listing_version_start, rsvo.ts_listing_version_start, pi.ts_price_started) AS ts_price_started,
        pi.ts_price_ended
    FROM
        rent_price_interval AS pi
    INNER JOIN
        rent_status_version_order AS rsvo
            ON rsvo.id_house = pi.id_house
            AND IF(
                rsvo.is_first_version AND pi.ts_price_started < rsvo.ts_listing_version_start,
                rsvo.ts_listing_version_start BETWEEN pi.ts_price_started AND COALESCE(pi.ts_price_ended, TO_TIMESTAMP(CURRENT_DATE)),
                pi.ts_price_started BETWEEN rsvo.ts_listing_version_start AND COALESCE(rsvo.ts_listing_version_end, TO_TIMESTAMP(CURRENT_DATE))
            )
),
sale_price_changes_listing AS (
    SELECT
        pi.id_house,
        ssvo.id_house_listing,
        pi.id_user_revision,
        pi.id_revision,
        pi.business_context,
        pi.sale_price AS price,
        LAG(pi.sale_price) OVER (PARTITION BY pi.id_house ORDER BY ts_price_started) AS lag_price,
        pi.is_last_price_of_day,
        IF(pi.ts_price_started < ssvo.ts_listing_version_start, ssvo.ts_listing_version_start, pi.ts_price_started) AS ts_price_started,
        pi.ts_price_ended
    FROM
        sale_price_interval AS pi
    INNER JOIN
        sale_status_version_order AS ssvo
            ON ssvo.id_house = pi.id_house
            AND IF(
                ssvo.is_first_version AND pi.ts_price_started < ssvo.ts_listing_version_start,
                ssvo.ts_listing_version_start BETWEEN pi.ts_price_started AND COALESCE(pi.ts_price_ended, TO_TIMESTAMP(CURRENT_DATE)),
                pi.ts_price_started BETWEEN ssvo.ts_listing_version_start AND COALESCE(ssvo.ts_listing_version_end, TO_TIMESTAMP(CURRENT_DATE))
            )
),
rent_price_changes_variation AS (
    SELECT
        id_house,
        id_house_listing,
        id_user_revision,
        id_revision,
        business_context,
        price,
        lag_price AS previous_price,
        CASE
            WHEN price - lag_price < 0 THEN 'PRICE_DECREASE'
            WHEN price - lag_price > 0 THEN 'PRICE_INCREASE'
            ELSE 'FIRST_PRICE'
        END AS change_type,
        (price - lag_price)/NULLIF(lag_price, 0) AS last_price_variation,
        (price - MIN(IF(lag_price IS NULL, price, NULL)) OVER (PARTITION BY id_house))/NULLIF(MIN(IF(lag_price IS NULL, price, NULL)) OVER (PARTITION BY id_house), 0) AS first_price_variation,
        IF(lag_price IS NULL, TRUE, FALSE) AS is_first_price,
        IF(ROW_NUMBER() OVER (PARTITION BY id_house, DATE(ts_price_started) ORDER BY ts_price_started DESC) = 1, TRUE, FALSE) AS is_last_price_of_day,
        ts_price_started,
        ts_price_ended
    FROM
    rent_price_changes_listing
),
sale_price_changes_variation AS (
    SELECT
        id_house,
        id_house_listing,
        id_user_revision,
        id_revision,
        business_context,
        price,
        lag_price AS previous_price,
        CASE
            WHEN price - lag_price < 0 THEN 'PRICE_DECREASE'
            WHEN price - lag_price > 0 THEN 'PRICE_INCREASE'
            ELSE 'FIRST_PRICE'
        END AS change_type,
        (price - lag_price)/NULLIF(lag_price, 0) AS last_price_variation,
        (price - MIN(IF(lag_price IS NULL, price, NULL)) OVER (PARTITION BY id_house))/NULLIF(MIN(IF(lag_price IS NULL, price, NULL)) OVER (PARTITION BY id_house), 0) AS first_price_variation,
        IF(lag_price IS NULL, TRUE, FALSE) AS is_first_price,
        is_last_price_of_day,
        ts_price_started,
        ts_price_ended
    FROM
    sale_price_changes_listing
)
SELECT
    id_house,
    id_house_listing,
    id_user_revision,
    id_revision,
    business_context,
    price,
    previous_price,
    ROUND(last_price_variation, 4) AS last_price_variation,
    ROUND(
        CASE
            WHEN is_first_price THEN NULLIF(first_price_variation, 0)
            ELSE first_price_variation
        END,
        4
    ) AS first_price_variation,
    change_type,
    ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY ts_price_started ASC) AS change_number,
    DATEDIFF(COALESCE(ts_price_ended, CURRENT_DATE), ts_price_started) AS days_with_pricing_scheme,
    is_last_price_of_day,
    is_first_price,
    ts_price_started,
    ts_price_ended
FROM
rent_price_changes_variation

UNION ALL

SELECT
    id_house,
    id_house_listing,
    id_user_revision,
    id_revision,
    business_context,
    price,
    previous_price,
    ROUND(last_price_variation, 4) AS last_price_variation,
    ROUND(
        CASE
            WHEN is_first_price THEN NULLIF(first_price_variation, 0)
            ELSE first_price_variation
        END,
        4
    ) AS first_price_variation,
    change_type,
    ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY ts_price_started ASC) AS change_number,
    DATEDIFF(COALESCE(ts_price_ended, CURRENT_DATE), ts_price_started) AS days_with_pricing_scheme,
    is_last_price_of_day,
    is_first_price,
    ts_price_started,
    ts_price_ended
FROM
    sale_price_changes_variation
