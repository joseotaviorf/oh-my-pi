WITH sale_listing_offer_sent AS (
    SELECT
        DATE(ts_event) AS dt_event,
        company_uuid,
        location_id,
        COUNT(*) AS sale_offers_sent
    FROM
        reverse_listings_report.sale_listing_offer_sent
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
    GROUP BY 1,2,3
)
SELECT
    COALESCE(slos.location_id, dls.id_location) AS id_location,
    COALESCE(slos.company_uuid, dls.uuid_company) AS uuid_company,
    COALESCE(slos.sale_offers_sent, 0) AS count_sent,
    COALESCE(dls.sale_offers_sent, 0) AS count_received,
    COALESCE(slos.dt_event, DATE(dls.dt_entry)) AS dt_entry,
    {year} AS year,
    {month} AS month,
    {day} AS day
FROM
    sale_listing_offer_sent AS slos
FULL OUTER JOIN
    datalake_reports_clean.daily_listings_summary AS dls
        ON slos.dt_event = DATE(dls.dt_entry)
        AND slos.company_uuid = dls.uuid_company
        AND slos.location_id = dls.id_location
WHERE
    COALESCE(dls.sale_offers_sent, 0) != COALESCE(slos.sale_offers_sent, 0)
    AND (
        dls.id IS NULL
        OR DATE(dls.dt_entry) = MAKE_DATE({year}, {month}, {day})
    )