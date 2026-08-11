-- Daily snapshot of published listings priced at or below 95% of the calculator's
-- suggested upper-bound price, used to target post-visit offer incentives.
WITH published_listings AS (
    SELECT
        lbc.id_house,
        lbc.business_context,
        IF(lbc.business_context = 'RENT', hse.rent, hse.sale_price) AS price
    FROM
        datalake_ebdb_clean.listing_business_context AS lbc
    INNER JOIN
        datalake_ebdb_clean.house AS hse
            ON hse.id = lbc.id_house
    WHERE
        LOWER(lbc.status) = 'published'
        AND IF(lbc.business_context = 'RENT', hse.rent, hse.sale_price) > 100
),
ranked_house_price_suggestion AS (
    SELECT
        id_house,
        business_context,
        suggested_upper_bound_price,
        suggestion_certainty,
        ROW_NUMBER() OVER (
            PARTITION BY id_house, business_context
            ORDER BY ts_updated DESC
        ) AS suggestion_recency_rank
    FROM
        datalake_ebdb_clean.house_price_suggestion
)
SELECT
    pli.id_house,
    pli.business_context,
    pli.price,
    hps.suggested_upper_bound_price AS price_reference,
    CURRENT_TIMESTAMP() AS ts_snapshot,
    YEAR(CURRENT_DATE()) AS year,
    MONTH(CURRENT_DATE()) AS month,
    DAY(CURRENT_DATE()) AS day
FROM
    published_listings AS pli
INNER JOIN
    ranked_house_price_suggestion AS hps
        ON hps.id_house = pli.id_house
        AND hps.business_context = pli.business_context
        AND hps.suggestion_recency_rank = 1
        AND hps.suggestion_certainty IN ('medium', 'high')
        AND pli.price <= (0.95 * hps.suggested_upper_bound_price)
