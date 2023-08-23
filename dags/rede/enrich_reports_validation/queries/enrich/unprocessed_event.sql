WITH all_events AS (
    SELECT
        id,
        'NEW_LISTING_TRAFFIC' AS source,
        ts_event
    FROM
        reverse_listings_report.sale_listing_traffic
    -- This filter is repeated for each table instead of being done only once at the end because year, month, day are partition cols. It is more efficient to filter by them before
    -- doing union all 
    WHERE 
        year = {year}
        AND month = {month}
        AND day = {day}
    UNION ALL
    SELECT
        id,
        'ONGOING_LISTINGS' AS source,
        ts_event
    FROM
        reverse_listings_report.sale_ongoing_listings
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
    UNION ALL
    SELECT
        id,
        'NEW_LISTING_VISIT_SCHEDULED' AS source,
        ts_event
    FROM
        reverse_listings_report.sale_listing_visit_scheduled
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
    UNION ALL
    SELECT
        id,
        'NEW_LISTING_VISIT_CONFIRMED' AS source,
        ts_event
    FROM
        reverse_listings_report.sale_listing_visit_confirmed
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
    UNION ALL
    SELECT
        id,
        'NEW_LISTING_OFFER_SENT' AS source,
        ts_event
    FROM
        reverse_listings_report.sale_listing_offer_sent
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
    UNION ALL
    SELECT
        id,
        'NEW_LISTING_OFFER_ACCEPTED' AS source,
        ts_event
    FROM
        reverse_listings_report.sale_listing_offer_accepted
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
    UNION ALL
    SELECT
        id,
        'NEW_LISTING_SIGNED_CONTRACT' AS source,
        ts_event
    FROM
        reverse_listings_report.sale_listing_signed_contract
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
)
SELECT
    ae.id AS id_event,
    ae.source,
    ae.ts_event,
    {year} AS year,
    {month} AS month,
    {day} AS day
FROM
    all_events AS ae
LEFT JOIN
    datalake_reports_clean.processed_event AS pe
        ON ae.id = pe.id_event
WHERE
    pe.id IS NULL