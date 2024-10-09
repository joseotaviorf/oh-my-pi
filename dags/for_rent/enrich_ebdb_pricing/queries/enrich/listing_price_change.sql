WITH house_aud AS (
    SELECT
        h_aud.id_house,
        lbc.business_context,
        r.id_user AS id_user_revision,
        h_aud.id_user AS id_owner,
        h_aud.id_region,
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
        id_owner,
        id_region,
        id_revision,
        sale_price,
        rent_price,
        reason,
        IF(ROW_NUMBER() OVER (PARTITION BY id_house, dt_change ORDER BY ts_revision DESC) = 1, TRUE, FALSE) AS is_last_price_of_day,
        ts_revision
    FROM
        house_aud
    WHERE
        /* Filter the last price before publication and all changes while published. (Avoids price changes before deciding on the price that will actually be published). */
        ((status_threshold = 'UNPUBLISHED' AND threshold = 1)
        OR (status_threshold = 'PUBLISHED' AND has_price_changed = TRUE))
        OR rev_type = 0
),
rent_price_changes_clean AS (
    SELECT
        id_house,
        id_user_revision,
        id_owner,
        id_region,
        id_revision,
        rent_price,
        LAG(rent_price) OVER (PARTITION BY id_house ORDER BY ts_revision) AS lag_price,
        reason,
        is_last_price_of_day,
        ts_revision AS ts_price_started
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
        id_owner,
        id_region,
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
        id_owner,
        id_region,
        id_revision,
        rent_price,
        lag_price,
        CASE
            WHEN rent_price - lag_price < 0 THEN 'Price decrease'
            WHEN rent_price - lag_price > 0 THEN 'Price increase'
            ELSE 'First price'
        END AS change_type,
        (rent_price - lag_price)/NULLIF(lag_price, 0) AS last_price_variation,
        (rent_price - MIN(IF(lag_price IS NULL, rent_price, NULL)) OVER (PARTITION BY id_house))/NULLIF(MIN(IF(lag_price IS NULL, rent_price, NULL)) OVER (PARTITION BY id_house), 0) AS first_price_variation,
        IF(lag_price IS NULL, TRUE, FALSE) AS is_first_price,
        is_last_price_of_day,
        ts_price_started,
        LEAD(ts_price_started) OVER (PARTITION BY id_house ORDER BY ts_price_started) AS ts_price_ended
    FROM
        rent_price_changes_clean
),
sale_price_changes_enriched AS (
    SELECT
        id_house,
        id_user_revision,
        id_owner,
        id_region,
        id_revision,
        sale_price,
        lag_sale_price,
        CASE
            WHEN sale_price - lag_sale_price < 0 THEN 'price down'
            WHEN sale_price - lag_sale_price > 0 THEN 'price up'
            ELSE 'first price'
        END AS change_type,
        (sale_price - lag_sale_price)/NULLIF(lag_sale_price, 0) AS last_price_variation,
        (sale_price - MIN(IF(lag_sale_price IS NULL, sale_price, null)) OVER (PARTITION BY id_house))/NULLIF(MIN(IF(lag_sale_price IS NULL, sale_price, null)) OVER (PARTITION BY id_house), 0) AS first_price_variation,
        IF(lag_sale_price IS NULL, TRUE, FALSE) AS is_first_price,
        is_last_price_of_day,
        IF(reason LIKE '%SmP%', TRUE, FALSE) AS is_smart_price_change,
        ts_price_started,
        LEAD(ts_price_started) OVER (PARTITION BY id_house ORDER BY ts_price_started) AS ts_price_ended
    FROM
        sale_price_changes_clean
),
rent_price_changes AS (
    SELECT
        id_house,
        CASE
            WHEN is_first_price = TRUE THEN id_owner
            ELSE id_user_revision
        END AS id_user_revision,
        id_owner,
        id_region,
        id_revision,
            CASE
            WHEN is_first_price = TRUE THEN 'PUBLISHED'
            ELSE NULL
        END AS status,
        rent_price,
        lag_price,
        ROUND(last_price_variation, 4) AS last_price_variation,
        ROUND(
            CASE
                WHEN is_first_price THEN NULLIF(first_price_variation, 0)
                ELSE first_price_variation
            END,
        4) AS first_price_variation,
        change_type,
        ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY ts_price_started ASC) AS change_number,
        DATEDIFF(COALESCE(ts_price_ended, CURRENT_DATE), ts_price_started) AS days_with_pricing_scheme,
        ts_price_ended IS NULL AS is_last_price,
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
        CASE
            WHEN is_first_price = TRUE THEN id_owner
            ELSE id_user_revision
        END AS id_user_revision,
        id_owner,
        id_region,
        id_revision,
        CASE
            WHEN is_first_price = TRUE THEN 'PUBLISHED'
            ELSE NULL
        END AS status,
        sale_price,
        lag_sale_price,
        ROUND(last_price_variation, 4) AS last_price_variation,
        ROUND(
            CASE
                WHEN is_first_price THEN NULLIF(first_price_variation, 0)
                ELSE first_price_variation
            END,
        4) AS first_price_variation,
        change_type,
        ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY ts_price_started ASC) AS change_number,
        DATEDIFF(COALESCE(ts_price_ended, CURRENT_DATE), ts_price_started) AS days_with_pricing_scheme,
        ts_price_ended IS NULL AS is_last_price,
        is_last_price_of_day,
        is_first_price,
        is_smart_price_change,
        ts_price_started,
        ts_price_ended
    FROM
        sale_price_changes_enriched
    WHERE
        sale_price != lag_sale_price
        OR lag_sale_price IS NULL
),
sale_status_version_order AS (
    SELECT
        id_house,
        status_history,
        IF(ROW_NUMBER() OVER (PARTITION BY id_house, DATE(ts_status_changed) ORDER BY ts_status_changed DESC)=1, TRUE, FALSE) AS is_last_status_of_day,
        ts_status_changed AS ts_status_started,
        COALESCE(LEAD(ts_status_changed) OVER (PARTITION BY id_house ORDER BY ts_status_changed), TO_TIMESTAMP(CURRENT_DATE)) AS ts_status_ended
    FROM
        datalake_sale_listings.sale_status_version_order
),
rent_status_version_order AS (
    SELECT
        id_house,
        id_house_listing,
        status_history,
        is_last_status_of_day,
        ts_status_started,
        COALESCE(LEAD(ts_status_started) OVER (PARTITION BY id_house ORDER BY ts_status_started), TO_TIMESTAMP(CURRENT_DATE)) AS ts_status_ended
    FROM
        datalake_ebdb_listing.house_listing_status
),
rent_calculator_changes AS (
    SELECT
        hpp_aud.id_house,
        hpp_aud.p_10,
        hpp_aud.p_30,
        hpp_aud.p_50,
        hpp_aud.p_70,
        hpp_aud.p_90,
        hpp_aud.certainty,
        IF(ROW_NUMBER() OVER (PARTITION BY hpp_aud.id_house, DATE(r.ts_revision) ORDER BY hpp_aud.rev DESC)=1, TRUE, FALSE) AS is_last_status_of_day,
        r.ts_revision AS ts_calculator_result_started,
        COALESCE(LEAD(r.ts_revision) OVER (PARTITION BY id_house ORDER BY r.ts_revision), TO_TIMESTAMP(CURRENT_DATE)) AS ts_calculator_result_ended
    FROM
        datalake_ebdb_clean.house_predicted_price_aud AS hpp_aud
    INNER JOIN
        datalake_ebdb_user.user_revision_entity AS r
            ON hpp_aud.rev = r.id
    WHERE
        business_context = 'RENT'
),
sale_calculator_changes AS (
    SELECT
        hpp_aud.id_house,
        hpp_aud.p_10,
        hpp_aud.p_30,
        hpp_aud.p_50,
        hpp_aud.p_70,
        hpp_aud.p_90,
        hpp_aud.certainty,
        IF(ROW_NUMBER() OVER (PARTITION BY hpp_aud.id_house, DATE(r.ts_revision) ORDER BY hpp_aud.rev DESC)=1, TRUE, FALSE) AS is_last_status_of_day,
        r.ts_revision AS ts_calculator_result_started,
        COALESCE(LEAD(r.ts_revision) OVER (PARTITION BY id_house ORDER BY r.ts_revision), TO_TIMESTAMP(CURRENT_DATE)) AS ts_calculator_result_ended
    FROM
        datalake_ebdb_clean.house_predicted_price_aud AS hpp_aud
    INNER JOIN
        datalake_ebdb_user.user_revision_entity AS r
            ON hpp_aud.rev = r.id
    WHERE
        business_context = 'SALE'
)
SELECT
    pc.id_house,
    rls.id_house_listing,
    pc.id_user_revision,
    pc.id_owner,
    pc.id_region,
    pc.id_revision,
    'RENT' AS business_context,
    COALESCE(pc.status, rls.status_history, 'PUBLISHED') AS status_history,
    pc.rent_price AS price,
    pc.lag_price AS previous_price,
    pc.last_price_variation,
    pc.first_price_variation,
    pc.change_type,
    pc.change_number,
    pc.days_with_pricing_scheme,
    cc.p_10 AS calculator_min_price,
    cc.p_30 AS calculator_p30_price,
    cc.p_50 AS calculator_price,
    cc.p_70 AS calculator_p70_price,
    cc.p_90 AS calculator_max_price,
    cc.certainty AS calculator_certainty,
    COALESCE(rls.is_last_status_of_day, cc.is_last_status_of_day) AS is_last_status_of_day,
    pc.is_first_price,
    pc.is_last_price,
    pc.is_last_price_of_day,
    a.id IS NOT NULL AS is_smart_price_change,
    pc.ts_price_started,
    pc.ts_price_ended
FROM
    rent_price_changes AS pc
LEFT JOIN
    rent_status_version_order AS rls
        ON rls.id_house = pc.id_house
        AND pc.ts_price_started BETWEEN rls.ts_status_started AND COALESCE(rls.ts_status_ended, TO_TIMESTAMP(CURRENT_DATE))
LEFT JOIN
    rent_calculator_changes AS cc
        ON cc.id_house = pc.id_house
        AND pc.ts_price_started BETWEEN cc.ts_calculator_result_started AND cc.ts_calculator_result_ended
LEFT JOIN
    datalake_ebdb_clean.dynamic_pricing_house_aud AS a
        ON a.rev = pc.id_revision
        AND a.mod_price_changes_occurred
        AND a.occurred_price_changes > 0

UNION ALL

SELECT
    pc.id_house,
    NULL AS id_house_listing,
    pc.id_user_revision,
    pc.id_owner,
    pc.id_region,
    pc.id_revision,
    'SALE' AS business_context,
    COALESCE(pc.status, sls.status_history, 'PUBLISHED') AS status_history,
    pc.sale_price AS price,
    pc.lag_sale_price AS previous_price,
    pc.last_price_variation,
    pc.first_price_variation,
    pc.change_type,
    pc.change_number,
    pc.days_with_pricing_scheme,
    cc.p_10 AS calculator_min_price,
    cc.p_30 AS calculator_p30_price,
    cc.p_50 AS calculator_price,
    cc.p_70 AS calculator_p70_price,
    cc.p_90 AS calculator_max_price,
    cc.certainty AS calculator_certainty,
    COALESCE(sls.is_last_status_of_day, cc.is_last_status_of_day) AS is_last_status_of_day,
    pc.is_first_price,
    pc.is_last_price,
    pc.is_last_price_of_day,
    pc.is_smart_price_change,
    pc.ts_price_started,
    pc.ts_price_ended
FROM
    sale_price_changes AS pc
LEFT JOIN
    sale_status_version_order AS sls
        ON sls.id_house = pc.id_house
        AND pc.ts_price_started BETWEEN sls.ts_status_started AND COALESCE(sls.ts_status_ended, TO_TIMESTAMP(CURRENT_DATE))
LEFT JOIN
    sale_calculator_changes AS cc
        ON cc.id_house = pc.id_house
        AND pc.ts_price_started BETWEEN cc.ts_calculator_result_started AND cc.ts_calculator_result_ended
