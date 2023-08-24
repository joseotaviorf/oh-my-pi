WITH sale_listing_visit_confirmed AS (
    SELECT
        DATE(ts_event) AS dt_event,
        company_uuid,
        location_id,
        COUNT(*) AS sale_visits_confirmed
    FROM
        reverse_listings_report.sale_listing_visit_confirmed
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
    GROUP BY 1,2,3
)
SELECT
    COALESCE(slvc.location_id, dls.id_location) AS id_location,
    COALESCE(slvc.company_uuid, dls.uuid_company) AS uuid_company,
    COALESCE(slvc.sale_visits_confirmed, 0) AS count_sent,
    COALESCE(dls.sale_visits_confirmed, 0) AS count_received,
    COALESCE(slvc.dt_event, DATE(dls.dt_entry)) AS dt_entry,
    {year} AS year,
    {month} AS month,
    {day} AS day
FROM
    sale_listing_visit_confirmed AS slvc
FULL OUTER JOIN
    datalake_reports_clean.daily_listings_summary AS dls
        ON slvc.dt_event = DATE(dls.dt_entry)
        AND slvc.company_uuid = dls.uuid_company
        AND slvc.location_id = dls.id_location
WHERE
    COALESCE(dls.sale_visits_confirmed, 0) != COALESCE(slvc.sale_visits_confirmed, 0)
    AND (
        dls.id IS NULL
        OR DATE(dls.dt_entry) = MAKE_DATE({year}, {month}, {day})
    )