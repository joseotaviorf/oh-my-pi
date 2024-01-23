WITH deleted_rows AS (
    SELECT
        id AS id_deleted_row
    FROM
        datalake_company_clean.revenue_share_aud
    WHERE
        rev_type = 2
)
SELECT
    id,
    company_id AS id_company,
    revenue_share_uuid AS uuid_revenue_share,
    commission,
    demand_fee,
    supply_fee,
    platform_fee,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.revenue_share AS r
LEFT JOIN
    deleted_rows AS dr
        ON dr.id_deleted_row = r.id
WHERE
    dr.id_deleted_row IS NULL
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) = 1
