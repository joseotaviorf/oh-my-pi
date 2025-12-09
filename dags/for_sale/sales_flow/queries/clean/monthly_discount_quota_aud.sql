SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    year_month,
    max_allowed,
    current_given,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.monthly_discount_quota_aud

