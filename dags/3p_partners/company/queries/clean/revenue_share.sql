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
    datalake_company_raw.revenue_share