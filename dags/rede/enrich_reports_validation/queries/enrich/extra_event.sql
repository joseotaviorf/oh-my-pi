WITH all_events AS (
    SELECT
        id
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
        id
    FROM
        reverse_listings_report.sale_ongoing_listings
    WHERE 
        year = {year}
        AND month = {month}
        AND day = {day}
    UNION ALL
    SELECT
        id
    FROM
        reverse_listings_report.sale_listing_visit_scheduled
    WHERE 
        year = {year}
        AND month = {month}
        AND day = {day}
    UNION ALL
    SELECT
        id
    FROM
        reverse_listings_report.sale_listing_visit_confirmed
    WHERE 
        year = {year}
        AND month = {month}
        AND day = {day}
    UNION ALL
    SELECT
        id
    FROM
        reverse_listings_report.sale_listing_offer_sent
    WHERE 
        year = {year}
        AND month = {month}
        AND day = {day}
    UNION ALL
    SELECT
        id
    FROM
        reverse_listings_report.sale_listing_offer_accepted
    WHERE 
        year = {year}
        AND month = {month}
        AND day = {day}
    UNION ALL
    SELECT
        id
    FROM
        reverse_listings_report.sale_listing_signed_contract
    WHERE 
        year = {year}
        AND month = {month}
        AND day = {day}
)
SELECT
    pe.id_event,
    pe.ts_created AS ts_processed,
    {year} AS year,
    {month} AS month,
    {day} AS day
FROM
    datalake_reports_clean.processed_event AS pe
LEFT JOIN
    all_events AS ae
        ON ae.id = pe.id_event
WHERE
    ae.id IS NULL
    AND MAKE_DATE(pe.year, pe.month, pe.day) = DATE_ADD(MAKE_DATE({year}, {month}, {day}), 1)
    -- We're comparing the events from the previous day to what was received by the Reports Service today