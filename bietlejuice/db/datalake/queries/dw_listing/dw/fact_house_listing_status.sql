WITH listing_business_context AS (
    SELECT id_house,
	   MAX(is_sale_context) AS is_for_sale,
	   MAX(is_rent_context) AS is_for_rent
    FROM
       datalake_ebdb_listing.listing_business_context
    GROUP BY 1
)
SELECT -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
    hls.id_house_listing AS sk_house_listing,
    COALESCE(hls.id_region, -1) AS sk_region,
    COALESCE(CAST(DATE_FORMAT(hls.ts_first_publication, "yyyyMMdd") AS BIGINT), -1) AS sk_first_publication_date,
    COALESCE(CAST(DATE_FORMAT(hls.ts_status_started, "yyyyMMdd") AS BIGINT), -1) AS sk_status_start_date,
    COALESCE(CAST(DATE_FORMAT(hls.ts_status_ended, "yyyyMMdd") AS BIGINT), -1) AS sk_status_end_date,
    hls.ts_status_started AS ts_status_start,
    hls.ts_status_ended AS ts_status_end,
    hls.status_history,
    LEFT(hls.status_change_reason, 5000) AS status_change_reason,
    COALESCE(
        -- get max ts per id_house_listing per day
        MAX(hls.ts_status_started) OVER(
            PARTITION BY hls.id_house_listing, CAST(hls.ts_status_started AS DATE)
        ) = hls.ts_status_started,
        FALSE) AS is_last_status_of_day,
    CAST(NOW() AS TIMESTAMP) AS ts_load
FROM datalake_ebdb_listing.house_listing_status hls
JOIN datalake_ebdb_listing.house_listing hl
    ON hl.id_house_listing = hls.id_house_listing
JOIN datalake_ebdb_listing.house h
    ON h.id = hl.id_house
LEFT JOIN listing_business_context lbc
    ON lbc.id_house = h.id
WHERE
    lbc.id_house IS NULL
    OR lbc.is_for_rent