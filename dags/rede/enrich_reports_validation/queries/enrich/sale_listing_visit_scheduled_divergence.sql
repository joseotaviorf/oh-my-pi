WITH sale_listing_visit_scheduled AS (
    SELECT
        DATE(ts_event) AS dt_event,
        company_uuid,
        location_id,
        COUNT(*) AS sale_visits_scheduled
    FROM
        reverse_listings_report.sale_listing_visit_scheduled
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
    GROUP BY 1,2,3
)
SELECT
    COALESCE(slvs.location_id, dls.id_location) AS id_location,
    COALESCE(slvs.company_uuid, dls.uuid_company) AS uuid_company,
    COALESCE(slvs.sale_visits_scheduled, 0) AS count_sent,
    COALESCE(dls.sale_visits_scheduled, 0) AS count_received,
    COALESCE(slvs.dt_event, DATE(dls.dt_entry)) AS dt_entry,
    {year} AS year,
    {month} AS month,
    {day} AS day
FROM
    sale_listing_visit_scheduled AS slvs
FULL OUTER JOIN
    datalake_reports_clean.daily_listings_summary AS dls
        ON slvs.dt_event = DATE(dls.dt_entry)
        AND slvs.company_uuid = dls.uuid_company
        AND slvs.location_id = dls.id_location
WHERE
    COALESCE(dls.sale_visits_scheduled, 0) != COALESCE(slvs.sale_visits_scheduled, 0)
    AND (
        dls.id IS NULL
        OR DATE(dls.dt_entry) = MAKE_DATE({year}, {month}, {day})
    )