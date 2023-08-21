WITH deleted AS (
    SELECT
        id
    FROM
        datalake_reports_clean.daily_listings_summary_aud
    WHERE
        revtype = 2
)
SELECT
    dls.id,
    dls.location_id AS id_location,
    dls.company AS uuid_company,
    dls.sale_count,
    dls.sale_traffic,
    dls.sale_visits_scheduled,
    dls.sale_visits_confirmed,
    dls.sale_offers_sent,
    dls.sale_offers_accepted,
    dls.ccv,
    dls.ccvs_transacted_amount,
    dls.ongoing_listings,
    dls.version,
    dls.entry_date AS dt_entry,
    dls.created_at AS ts_created,
    dls.updated_at AS ts_updated
FROM
    datalake_reports_raw.daily_listings_summary AS dls
LEFT JOIN
    deleted AS d
        ON dls.id = d.id
WHERE
    d.id IS NULL
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY dls.id ORDER BY ts_updated DESC) = 1
