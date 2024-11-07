WITH house_aud AS (
    SELECT
        h_aud.id_house,
        lbc.business_context,
        r.id_user AS id_user_revision,
        h_aud.rev AS id_revision,
        h_aud.rev_type,
        h_aud.rent AS rent_price,
        h_aud.sale_price AS sale_price,
        CASE
            WHEN lbc.ts_first_publication >= r.ts_revision THEN 'UNPUBLISHED'
            ELSE 'PUBLISHED'
        END AS status_threshold,
        r.reason,
        /* The purpose of creating this threshold is to take the last line before the listing is published, so that we have the first price. */
        ROW_NUMBER() OVER (PARTITION BY h_aud.id_house, IF(lbc.ts_first_publication >= r.ts_revision, 'UNPUBLISHED', 'PUBLISHED') ORDER BY h_aud.rev DESC) AS threshold,
        /* We can't trust the mod_sale_price flag in 100% of cases, so we need to check if the price has changed manually. */
        LAG(h_aud.rent) OVER (PARTITION BY h_aud.id_house ORDER BY r.ts_revision, h_aud.rev) IS DISTINCT FROM h_aud.rent
            OR LAG(h_aud.sale_price) OVER (PARTITION BY h_aud.id_house ORDER BY r.ts_revision, h_aud.rev) IS DISTINCT FROM h_aud.sale_price AS has_price_changed,
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
        rent > 1
        OR sale_price > 1
),
price_changes_raw AS (
    SELECT
        id_house,
        business_context,
        id_user_revision,
        id_revision,
        sale_price,
        rent_price,
        reason,
        dt_change,
        ts_revision
    FROM
        house_aud
    WHERE
        /* Filter the last price before publication and all changes while published. (Avoids price changes before deciding on the price that will actually be published). */
        (
            (status_threshold = 'UNPUBLISHED' AND threshold = 1)
            OR (status_threshold = 'PUBLISHED' AND has_price_changed = TRUE)
        )
        OR rev_type = 0
),
rent_price_changes_clean AS (
    SELECT
        id_house,
        id_user_revision,
        id_revision,
        rent_price,
        LAG(rent_price) OVER (PARTITION BY id_house ORDER BY ts_revision) AS lag_price,
        reason,
        dt_change,
        ts_revision
    FROM
        price_changes_raw
    WHERE
        business_context = 'RENT'
    QUALIFY
        lag_price IS DISTINCT FROM rent_price
),
sale_price_changes_clean AS (
    SELECT
        id_house,
        id_user_revision,
        id_revision,
        sale_price,
        LAG(sale_price) OVER (PARTITION BY id_house ORDER BY ts_revision) AS lag_sale_price,
        reason,
        is_last_price_of_day,
        ts_revision AS ts_price_started
    FROM
        price_changes_raw
    WHERE
        business_context = 'SALE'
    QUALIFY
        lag_sale_price IS DISTINCT FROM sale_price
),
rent_price_changes_enriched AS (
    SELECT
        id_house,
        id_user_revision,
        id_revision,
        rent_price,
        lag_price,
        CASE
            WHEN rent_price - lag_price < 0 THEN 'PRICE_DECREASE'
            WHEN rent_price - lag_price > 0 THEN 'PRICE_INCREASE'
            ELSE 'FIRST_PRICE'
        END AS change_type,
        (rent_price - lag_price)/NULLIF(lag_price, 0) AS last_price_variation,
        (rent_price - MIN(IF(lag_price IS NULL, rent_price, NULL)) OVER (PARTITION BY id_house))/NULLIF(MIN(IF(lag_price IS NULL, rent_price, NULL)) OVER (PARTITION BY id_house), 0) AS first_price_variation,
        IF(lag_price IS NULL, TRUE, FALSE) AS is_first_price,
        IF(ROW_NUMBER() OVER (PARTITION BY id_house, dt_change ORDER BY ts_revision DESC) = 1, TRUE, FALSE) AS is_last_price_of_day,
        ts_revision AS ts_price_started,
        LEAD(ts_revision) OVER (PARTITION BY id_house ORDER BY ts_revision) AS ts_price_ended
    FROM
        rent_price_changes_clean
),
sale_price_changes_enriched AS (
    SELECT
        id_house,
        id_user_revision,
        id_revision,
        sale_price,
        lag_sale_price,
        CASE
            WHEN sale_price - lag_sale_price < 0 THEN 'PRICE_DECREASE'
            WHEN sale_price - lag_sale_price > 0 THEN 'PRICE_INCREASE'
            ELSE 'FIRST_PRICE'
        END AS change_type,
        (sale_price - lag_sale_price)/NULLIF(lag_sale_price, 0) AS last_price_variation,
        (sale_price - MIN(IF(lag_sale_price IS NULL, sale_price, null)) OVER (PARTITION BY id_house))/NULLIF(MIN(IF(lag_sale_price IS NULL, sale_price, null)) OVER (PARTITION BY id_house), 0) AS first_price_variation,
        IF(lag_sale_price IS NULL, TRUE, FALSE) AS is_first_price,
        is_last_price_of_day,
        ts_price_started,
        LEAD(ts_price_started) OVER (PARTITION BY id_house ORDER BY ts_price_started) AS ts_price_ended
    FROM
        sale_price_changes_clean
),
rent_price_changes AS (
    SELECT
        id_house,
        id_user_revision,
        id_revision,
        rent_price,
        lag_price,
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
        rent_price_changes_enriched
    WHERE
        rent_price != lag_price
        OR lag_price IS NULL
),
sale_price_changes AS (
    SELECT
        id_house,
        id_user_revision,
        id_revision,
        sale_price,
        lag_sale_price,
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
        sale_price_changes_enriched
    WHERE
        sale_price != lag_sale_price
        OR lag_sale_price IS NULL
),
rent_status_version_order AS (
    SELECT
        id_house,
        id_house_listing,
        MIN(ts_status_started) AS ts_status_started,
        MAX(ts_status_ended) AS ts_status_ended
    FROM
        datalake_ebdb_listing.house_listing_status
    GROUP BY
        1, 2
)
SELECT
    pc.id_house,
    rls.id_house_listing,
    pc.id_user_revision,
    pc.id_revision,
    'RENT' AS business_context,
    pc.rent_price AS price,
    pc.lag_price AS previous_price,
    pc.last_price_variation,
    pc.first_price_variation,
    pc.change_type,
    pc.change_number,
    pc.days_with_pricing_scheme,
    pc.is_first_price,
    pc.is_last_price_of_day,
    pc.ts_price_started,
    pc.ts_price_ended
FROM
    rent_price_changes AS pc
LEFT JOIN
    rent_status_version_order AS rls
        ON rls.id_house = pc.id_house
        AND pc.ts_price_started BETWEEN rls.ts_status_started AND COALESCE(rls.ts_status_ended, TO_TIMESTAMP(CURRENT_DATE))

UNION ALL

SELECT
    id_house,
    NULL AS id_house_listing,
    id_user_revision,
    id_revision,
    'SALE' AS business_context,
    sale_price AS price,
    lag_sale_price AS previous_price,
    last_price_variation,
    first_price_variation,
    change_type,
    change_number,
    days_with_pricing_scheme,
    is_first_price,
    is_last_price_of_day,
    ts_price_started,
    ts_price_ended
FROM
    sale_price_changes
