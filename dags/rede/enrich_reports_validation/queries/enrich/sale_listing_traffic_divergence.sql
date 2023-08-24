WITH sale_listing_traffic AS (
    SELECT
        DATE(ts_event) AS dt_event,
        company_uuid,
        location_id,
        SUM(traffic_count) AS traffic_count
    FROM
        reverse_listings_report.sale_listing_traffic
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
    GROUP BY 1,2,3
)
SELECT
    COALESCE(slt.location_id, dls.id_location) AS id_location,
    COALESCE(slt.company_uuid, dls.uuid_company) AS uuid_company,
    COALESCE(slt.traffic_count, 0) AS count_sent,
    COALESCE(dls.sale_traffic, 0) AS count_received,
    COALESCE(slt.dt_event, DATE(dls.dt_entry)) AS dt_entry,
    {year} AS year,
    {month} AS month,
    {day} AS day
FROM
    sale_listing_traffic AS slt
FULL OUTER JOIN
    datalake_reports_clean.daily_listings_summary AS dls
        ON slt.dt_event = DATE(dls.dt_entry)
        AND slt.company_uuid = dls.uuid_company
        AND slt.location_id = dls.id_location
WHERE
    COALESCE(dls.sale_traffic, 0) != COALESCE(slt.traffic_count, 0)
    AND (
        dls.id IS NULL
        OR DATE(dls.dt_entry) = MAKE_DATE({year}, {month}, {day})
    )