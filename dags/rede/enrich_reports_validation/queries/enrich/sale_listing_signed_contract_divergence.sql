WITH sale_listing_signed_contract AS (
    SELECT
        DATE(ts_event) AS dt_event,
        company_uuid,
        location_id,
        COUNT(*) AS ccv,
        SUM(contract_value) AS ccvs_transacted_amount
    FROM
        reverse_listings_report.sale_listing_signed_contract
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
    GROUP BY 1,2,3
)
SELECT
    COALESCE(slsc.location_id, dls.id_location) AS id_location,
    COALESCE(slsc.company_uuid, dls.uuid_company) AS uuid_company,
    COALESCE(slsc.ccv, 0) AS count_sent,
    COALESCE(slsc.ccvs_transacted_amount, 0) AS transacted_amount_sent,
    COALESCE(dls.ccv, 0) AS count_received,
    COALESCE(dls.ccvs_transacted_amount, 0) AS transacted_amount_received,
    COALESCE(slsc.dt_event, DATE(dls.dt_entry)) AS dt_entry,
    {year} AS year,
    {month} AS month,
    {day} AS day
FROM
    sale_listing_signed_contract AS slsc
FULL OUTER JOIN
    datalake_reports_clean.daily_listings_summary AS dls
        ON slsc.dt_event = DATE(dls.dt_entry)
        AND slsc.company_uuid = dls.uuid_company
        AND slsc.location_id = dls.id_location
WHERE
    (
        COALESCE(dls.ccv, 0) != COALESCE(slsc.ccv, 0)
        OR COALESCE(dls.ccvs_transacted_amount, 0) != COALESCE(slsc.ccvs_transacted_amount, 0)
    ) AND (
        dls.id IS NULL
        OR DATE(dls.dt_entry) = MAKE_DATE({year}, {month}, {day})
    )