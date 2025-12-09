SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    monthly_discount_quota_id AS id_monthly_discount_quota,
    sales_flow_id AS id_sales_flow,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.monthly_discount_quota_registry_aud

