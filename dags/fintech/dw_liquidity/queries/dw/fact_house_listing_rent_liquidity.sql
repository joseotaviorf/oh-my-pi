WITH ranked_listing_liquidity AS (
    SELECT
        hlr.id,
        hlr.id_house,
        hlr.model_version,
        hlr.rent_liquidity_score,
        hlr.timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY hlr.id
            ORDER BY hlr.timestamp DESC
        ) AS rn
    FROM
        wonka.house_listing_rent_liquidity AS hlr
)
SELECT
    rll.id AS sk_house_listing,
    rll.id_house AS sk_house,
    rll.model_version AS rent_liquidity_model_version,
    hl.status AS listing_status,
    rll.rent_liquidity_score,
    hl.ts_publicated,
    rll.timestamp AS ts_created,
    NOW() AS ts_load
FROM
    ranked_listing_liquidity AS rll
LEFT JOIN
    datalake_ebdb_listing.house_listing AS hl
        ON hl.id_house_listing = rll.id
WHERE
    rll.rn = 1
