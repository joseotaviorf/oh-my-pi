SELECT 
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    source,
    category,
    reason,
    active AS is_active,
    source_mod AS mod_source,
    category_mod AS mod_category,
    reason_mod AS mod_reason,
    active_mod AS mod_is_active,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.reject_reason_aud
