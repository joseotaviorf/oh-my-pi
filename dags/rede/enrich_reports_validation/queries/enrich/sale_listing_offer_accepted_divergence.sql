WITH sale_listing_offer_accepted AS (
    SELECT
        DATE(ts_event) AS dt_event,
        company_uuid,
        location_id,
        COUNT(*) AS sale_offers_accepted
    FROM
        reverse_listings_report.sale_listing_offer_accepted
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
    GROUP BY 1,2,3
)
SELECT
    COALESCE(sloa.location_id, dls.id_location) AS id_location,
    COALESCE(sloa.company_uuid, dls.uuid_company) AS uuid_company,
    COALESCE(sloa.sale_offers_accepted, 0) AS count_sent,
    COALESCE(dls.sale_offers_accepted, 0) AS count_received,
    COALESCE(sloa.dt_event, DATE(dls.dt_entry)) AS dt_entry,
    {year} AS year,
    {month} AS month,
    {day} AS day
FROM
    sale_listing_offer_accepted AS sloa
FULL OUTER JOIN
    datalake_reports_clean.daily_listings_summary AS dls
        ON sloa.dt_event = DATE(dls.dt_entry)
        AND sloa.company_uuid = dls.uuid_company
        AND sloa.location_id = dls.id_location
WHERE
    COALESCE(dls.sale_offers_accepted, 0) != COALESCE(sloa.sale_offers_accepted, 0)
    AND (
        dls.id IS NULL
        OR DATE(dls.dt_entry) = MAKE_DATE({year}, {month}, {day})
    )