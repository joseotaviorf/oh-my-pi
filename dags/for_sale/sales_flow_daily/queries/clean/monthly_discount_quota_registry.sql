SELECT
    id,
    monthly_discount_quota_id AS id_monthly_discount_quota,
    sales_flow_id AS id_sales_flow,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.monthly_discount_quota_registry

