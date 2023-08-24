WITH sale_ongoing_listings AS (
    SELECT
        DATE(ts_event) AS dt_event,
        company_uuid,
        location_id,
        SUM(ongoing_listings_count) AS ongoing_listings_count
    FROM
        reverse_listings_report.sale_ongoing_listings
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
    GROUP BY 1,2,3
)
SELECT
    COALESCE(sol.location_id, dls.id_location) AS id_location,
    COALESCE(sol.company_uuid, dls.uuid_company) AS uuid_company,
    COALESCE(sol.ongoing_listings_count, 0) AS count_sent,
    COALESCE(dls.ongoing_listings, 0) AS count_received,
    COALESCE(sol.dt_event, DATE(dls.dt_entry)) AS dt_entry,
    {year} AS year,
    {month} AS month,
    {day} AS day
FROM
    sale_ongoing_listings AS sol
FULL OUTER JOIN
    datalake_reports_clean.daily_listings_summary AS dls
        ON sol.dt_event = DATE(dls.dt_entry)
        AND sol.company_uuid = dls.uuid_company
        AND sol.location_id = dls.id_location
WHERE
    COALESCE(dls.ongoing_listings, 0) != COALESCE(sol.ongoing_listings_count, 0)
    AND (
        dls.id IS NULL
        OR DATE(dls.dt_entry) = MAKE_DATE({year}, {month}, {day})
    )